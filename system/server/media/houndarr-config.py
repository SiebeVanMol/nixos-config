"""Converge Houndarr's instance list from the media registry.

Houndarr keeps its instances - the Radarr/Sonarr/Lidarr URLs, their API keys and
every per-instance search control - in its own SQLite database behind a web UI
with session authentication. There is no configuration file and no environment
variable for any of it, and the one API key lane it exposes authorizes only the
read-only widget endpoint. So none of this is reachable from Nix, and a host
rebuilt from this repository would come back with a working Houndarr and an
empty instance list in it.

This fills that gap the way the rest of the stack does: as root, after the
applications are up, read each *arr application's API key out of the config.xml
it wrote for itself and write the instance row Houndarr would otherwise have
been clicked into. A repeat run is a no-op.

Two things about the coupling, because it is real and deliberate:

  * The API key is stored the way Houndarr stores it - Fernet-encrypted with the
    key in <data-dir>/houndarr.masterkey - so ``encrypt``/``decrypt`` below
    reimplement houndarr.crypto exactly. That module is three lines of Fernet;
    importing it instead would mean depending on Houndarr's importable package
    layout, which its application wrapper does not expose. The version is pinned
    in overlays/houndarr.nix.
  * The column names below are Houndarr's schema (version 21 at the pinned
    1.13.3). Only the columns this script owns are written; the walk cursors,
    the snapshot counts and the timestamps all belong to Houndarr and are left
    alone. A schema change therefore shows up as a sqlite3 error in the journal
    rather than as a silent misconfiguration.

The search controls are the point of the exercise, not an afterthought: the
values are declared and explained in houndarr.nix.
"""

import json
import os
import sqlite3
import subprocess
import sys
import time

from cryptography.fernet import Fernet, InvalidToken

import arr_client as arr

TAG = "[houndarr-config]"

# The instance types Houndarr's schema accepts, mapped to the (missing, upgrade)
# search-mode column pair each one uses. radarr maps to None: it has neither
# column, so its modes come from Houndarr's own defaults.
INSTANCE_TYPES = {
    "radarr": None,
    "sonarr": ("sonarr_search_mode", "upgrade_sonarr_search_mode"),
    "lidarr": ("lidarr_search_mode", "upgrade_lidarr_search_mode"),
    "readarr": ("readarr_search_mode", "upgrade_readarr_search_mode"),
    "whisparr_v2": ("whisparr_v2_search_mode", "upgrade_whisparr_v2_search_mode"),
}

# Everything this script owns in an `instances` row. The rest of the schema -
# upgrade_item_offset, missing_page_offset, monitored_total, the snapshot
# timestamps - is Houndarr's own bookkeeping and is never written here.
TUNING_COLUMNS = (
    "name",
    "url",
    "enabled",
    "missing_enabled",
    "batch_size",
    "sleep_interval_mins",
    "hourly_cap",
    "cooldown_days",
    "post_release_grace_hrs",
    "missing_hot_retry_window_hrs",
    "missing_hot_retry_interval_hrs",
    "queue_limit",
    "cutoff_enabled",
    "cutoff_batch_size",
    "cutoff_cooldown_days",
    "cutoff_hourly_cap",
    "upgrade_enabled",
    "upgrade_batch_size",
    "upgrade_cooldown_days",
    "upgrade_hourly_cap",
    "upgrade_series_window_size",
    "allowed_time_window",
    "search_order",
    "tag_filter_include",
    "tag_filter_exclude",
)

BOOLEAN_COLUMNS = frozenset({"enabled", "missing_enabled", "cutoff_enabled", "upgrade_enabled"})

RESTART_UNIT = "houndarr.service"


def log(message):
    print(f"{TAG} {message}", flush=True)


def warn(message):
    print(f"{TAG} WARNING: {message}", flush=True)


def load_config():
    path = os.environ.get("HOUNDARR_CONFIG")
    if not path:
        sys.exit(f"{TAG} HOUNDARR_CONFIG is not set")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


api_key = arr.api_key


def encrypt(plaintext, key):
    """Encrypt the way houndarr.crypto.encrypt does: a plain Fernet token."""
    return Fernet(key).encrypt(plaintext.encode()).decode()


def decrypt(token, key):
    return Fernet(key).decrypt(token.encode()).decode()


def read_master_key(data_dir):
    path = os.path.join(data_dir, "houndarr.masterkey")
    try:
        with open(path, "rb") as handle:
            return handle.read().strip()
    except OSError:
        return None


def wait_for_database(path, deadline):
    """Wait for Houndarr to have created and migrated its database.

    The instance table is the specific thing needed, so that is what is polled
    for rather than the file: Houndarr creates the file and then migrates it, and
    writing between the two would race the schema.
    """
    while time.monotonic() < deadline:
        if os.path.exists(path):
            try:
                con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
                try:
                    con.execute("SELECT 1 FROM instances LIMIT 1")
                finally:
                    con.close()
                return True
            except sqlite3.Error:
                pass
        time.sleep(2)
    return False


def wait_for_keys(apps, deadline):
    """Wait until every application has written the config.xml holding its key.

    At boot these units start together and an application writes config.xml a
    second or two after it starts, so reading once would make a cold boot depend
    on winning a race - and losing it means waiting for the daily timer. Polling
    here is what lets one pass converge everything.

    Returns the keys that appeared; a caller decides what to do about the rest,
    because a partially converged run is much better than none.
    """
    keys = {}
    pending = dict(apps)
    while pending and time.monotonic() < deadline:
        for name, app in list(pending.items()):
            value = api_key(app["dir"])
            if value:
                keys[name] = value
                del pending[name]
        if pending:
            time.sleep(2)
    for name in pending:
        warn(f"{name}: no API key readable from {apps[name]['dir']} before the deadline")
    return keys


def desired_row(app, tuning):
    """The columns this script wants for one instance, typed for SQLite."""
    instance_type = (app.get("implementation") or "").lower()

    row = {}
    for column in TUNING_COLUMNS:
        if column in ("name", "url"):
            continue
        if column in tuning:
            value = tuning[column]
            row[column] = int(value) if column in BOOLEAN_COLUMNS else value

    row["name"] = app["implementation"]
    row["url"] = f"http://{app['host']}:{app['port']}"

    modes = INSTANCE_TYPES.get(instance_type)
    if modes:
        missing_mode, upgrade_mode = modes
        for column, lookup in (
            (missing_mode, "search_modes"),
            (upgrade_mode, "upgrade_search_modes"),
        ):
            if instance_type in tuning.get(lookup, {}):
                row[column] = tuning[lookup][instance_type]
    return row


def find_row(con, instance_type, name):
    """Find the row for this application, without guessing between two installs."""
    rows = con.execute(
        "SELECT * FROM instances WHERE lower(type) = ? ORDER BY id", (instance_type,)
    ).fetchall()
    if not rows:
        return None
    for row in rows:
        if (row["name"] or "").lower() == (name or "").lower():
            return row
    if len(rows) == 1:
        return rows[0]
    warn(
        f"{len(rows)} {instance_type} instances exist and none is named {name!r}; "
        "leaving them alone rather than guessing which one this is"
    )
    return None


def key_matches(stored, api_key_value, key):
    if not stored:
        return False
    try:
        return decrypt(stored, key) == api_key_value
    except (InvalidToken, ValueError, TypeError):
        return False


def converge(con, app, api_key_value, tuning, key):
    """Create or update one instance. Returns the number of columns changed."""
    instance_type = (app.get("implementation") or "").lower()
    if instance_type not in INSTANCE_TYPES:
        warn(f"{app['implementation']}: Houndarr has no instance type for it; skipping")
        return 0

    desired = desired_row(app, tuning)
    existing = find_row(con, instance_type, desired["name"])

    if existing is None:
        columns = ["type", "encrypted_api_key", *desired]
        values = [instance_type, encrypt(api_key_value, key), *desired.values()]
        con.execute(
            f"INSERT INTO instances ({', '.join(columns)}) "
            f"VALUES ({', '.join('?' for _ in columns)})",
            values,
        )
        log(f"{app['implementation']}: created the instance ({desired['url']})")
        return len(columns)

    changed = {column: value for column, value in desired.items() if existing[column] != value}

    # The key is compared by decrypting it rather than by comparing ciphertext:
    # Fernet output differs on every call, so an equality check on the stored
    # token would report drift forever. This is also what catches an *arr
    # application that regenerated its key.
    if not key_matches(existing["encrypted_api_key"], api_key_value, key):
        changed["encrypted_api_key"] = encrypt(api_key_value, key)

    if not changed:
        log(f"{app['implementation']}: already converged")
        return 0

    con.execute(
        f"UPDATE instances SET {', '.join(f'{column} = ?' for column in changed)}, "
        "updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?",
        [*changed.values(), existing["id"]],
    )
    if "encrypted_api_key" in changed:
        others = len(changed) - 1
        log(f"{app['implementation']}: refreshed its API key and {others} other setting(s)")
    else:
        log(f"{app['implementation']}: converged {', '.join(sorted(changed))}")
    return len(changed)


def restart_houndarr():
    """Make Houndarr reload the rows it read at startup.

    The supervisor re-reads the instance list for its snapshot refresh, but each
    scheduled search task keeps the object it was started with, so a setting
    written underneath a running pass would take effect at an unpredictable
    point. A restart is about a second and removes the ambiguity.
    """
    try:
        subprocess.run(
            ["systemctl", "try-restart", "--no-block", RESTART_UNIT],
            check=False,
            timeout=30,
        )
        log(f"asked systemd to restart {RESTART_UNIT} so the new settings load")
    except (OSError, subprocess.SubprocessError) as error:
        warn(f"could not restart {RESTART_UNIT}: {error}")


def main():
    config = load_config()
    apps = config.get("apps") or {}
    tuning = config.get("tuning") or {}
    deadline = time.monotonic() + config.get("wait_seconds", 60)

    if not apps:
        log("no *arr applications registered; nothing to converge")
        return 0

    if not wait_for_database(config["database"], deadline):
        # Not an error: on a first install Houndarr has to run once to create
        # its database, and the daily timer or the next switch converges it.
        log("Houndarr has not created its database yet; nothing to converge")
        return 0

    key = read_master_key(config["data_dir"])
    if key is None:
        warn(f"no master key in {config['data_dir']}; Houndarr creates it on first run")
        return 1

    keys = wait_for_keys(apps, deadline)
    if not keys:
        warn("no application had a readable API key; nothing to converge")
        return 1

    changed = 0
    con = sqlite3.connect(config["database"], timeout=30)
    try:
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA busy_timeout = 30000")
        # One transaction, so Houndarr never reads a half-applied instance list.
        with con:
            for name in sorted(keys):
                changed += converge(con, apps[name], keys[name], tuning, key)
    except sqlite3.Error as error:
        warn(f"database error: {error}")
        return 1
    finally:
        con.close()

    if changed and config.get("restart", True):
        restart_houndarr()

    skipped = len(apps) - len(keys)
    summary = f"{changed} change(s)"
    if skipped:
        summary += f"; {skipped} application(s) had no key yet"
    log(f"done with {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
