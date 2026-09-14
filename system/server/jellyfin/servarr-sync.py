"""Declarative settings sync for the Servarr stack.

The NixOS configuration declares the services; this script converges the
settings that would otherwise have to be clicked in six different web UIs:

  * Prowlarr: register every *arr as an application, so Prowlarr pushes its
    indexers to them, and add FlareSolverr as an indexer proxy.
  * Sonarr/Radarr/Lidarr/Readarr: add Transmission as the download client at
    the VPN namespace address, with the same per-category directory the
    tmpfiles rules already create on /Vault/Downloads.
  * Readarr: warn when the shared ebook root folder is missing.

Two properties matter and are deliberate:

  * No secret is ever passed in. Every API key is read at runtime out of the
    application's own config.xml, because the Nix store is world readable and
    this repository already refuses to put the Prowlarr key in an environment
    variable for exactly that reason.
  * Runs are idempotent. Each setting is compared against the live value and
    only written when it differs, so a second run changes nothing.

The connection details arrive as a JSON file through SERVARR_SYNC_CONFIG; see
the accompanying Nix module for what it contains.
"""

import glob
import json
import os
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

TAG = "[servarr-sync]"
CLIENT_NAME = "Transmission"
PROXY_NAME = "FlareSolverr"
NOTIFICATION_NAME = "Alerts"
SEERR_PORT = 5055
POLL_SECONDS = 2


def log(message):
    print(f"{TAG} {message}", flush=True)


def warn(message):
    print(f"{TAG} WARNING: {message}", flush=True)


class ApiError(Exception):
    """An API call that could not be completed."""

    def __init__(self, message, status=None):
        super().__init__(message)
        # The HTTP status, when the server answered at all. A reply - even a
        # 401 - proves the application is up, which is a different thing from a
        # connection that was refused.
        self.status = status


def load_config():
    path = os.environ.get("SERVARR_SYNC_CONFIG")
    if not path:
        sys.exit(f"{TAG} SERVARR_SYNC_CONFIG is not set")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def api_key(app_dir):
    """Return the API key an application wrote into its own config.xml.

    Where that file lives depends on how the service was started, so both
    layouts are tried: Prowlarr is launched with -data=/var/lib/prowlarr and
    keeps config.xml directly in that directory, while Sonarr, Radarr and
    Lidarr are launched with -data=/var/lib/<app>/.config/<Project> and keep it
    one level further down. Getting this wrong is not a soft failure - the
    application then never looks ready and the caller waits out its deadline.
    """
    candidates = [os.path.join(app_dir, "config.xml")]
    candidates += sorted(glob.glob(os.path.join(app_dir, ".config", "*", "config.xml")))
    for path in candidates:
        try:
            root = ET.parse(path).getroot()
        except (OSError, ET.ParseError):
            continue
        node = root.find("ApiKey")
        if node is not None and (node.text or "").strip():
            return node.text.strip()
    return None


def _describe_error(detail):
    """Turn an *arr error body into one readable line.

    These APIs answer with a JSON array of validation objects, which is
    unreadable in a journal at 300 characters and says nothing about what to do.
    Pull out the message and the offending property/value instead.
    """
    try:
        payload = json.loads(detail)
    except json.JSONDecodeError:
        return " ".join(detail.split())[:200]
    if not isinstance(payload, list):
        return " ".join(detail.split())[:200]
    parts = []
    for item in payload[:3]:
        if not isinstance(item, dict):
            continue
        message = item.get("errorMessage") or item.get("message") or item.get("errorCode") or ""
        placeholders = item.get("formattedMessagePlaceholderValues") or {}
        prop = placeholders.get("PropertyName")
        value = placeholders.get("PropertyValue") or placeholders.get("AttemptedValue")
        if prop:
            message = f"{message} [{prop}={value}]" if message else f"[{prop}={value}]"
        if message:
            parts.append(message.strip())
    return "; ".join(parts)[:300] if parts else " ".join(detail.split())[:200]


def call(port, version, key, method, path, body=None, timeout=30):
    """Call one of the *arr APIs on loopback and return the decoded body."""
    url = f"http://127.0.0.1:{port}/api/{version}{path}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("X-Api-Key", key)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:600]
        raise ApiError(
            f"{method} {path} -> HTTP {error.code}: {_describe_error(detail)}",
            status=error.code,
        ) from error
    except (urllib.error.URLError, OSError) as error:
        raise ApiError(f"{method} {path} -> {error}") from error
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ApiError(f"{method} {path} -> unparseable response") from error


def probe(port, key):
    """Classify a running application.

    Returns (version, state) where state is one of "ok" (it answered and
    accepted the key), "unauthorized" (it answered but rejected the key - a
    config problem that waiting cannot fix) or "down" (nothing answered yet).

    Sonarr/Radarr answer on v3 while Lidarr/Readarr/Prowlarr answer on v1, and
    probing removes the need to hardcode that per application.
    """
    saw_response = False
    for version in ("v3", "v1"):
        try:
            call(port, version, key, "GET", "/system/status", timeout=5)
            return version, "ok"
        except ApiError as error:
            if error.status is not None:
                saw_response = True
    return None, "unauthorized" if saw_response else "down"


def wait_ready(apps, deadline):
    """Poll every application until it answers, or the deadline passes.

    Progress is logged as it happens: an earlier version of this loop ran
    silently for its full five minutes, which looked exactly like a hung system
    from the outside (it was holding up a nixos-rebuild, so the diagnosis
    mattered).
    """
    ready = {}
    pending = dict(apps)
    while pending and time.monotonic() < deadline:
        for name, spec in list(pending.items()):
            key = api_key(spec["dir"])
            if key is None:
                continue
            version, state = probe(spec["port"], key)
            if state == "ok":
                ready[name] = {"key": key, "version": version, **spec}
                log(f"{name}: ready on the {version} API")
                del pending[name]
            elif state == "unauthorized":
                warn(
                    f"{name}: it is running but rejected the API key read from "
                    f"{spec['dir']}; skipping (check that the key file is current)"
                )
                del pending[name]
        if pending:
            time.sleep(POLL_SECONDS)
    for name in pending:
        warn(f"{name}: no response before the deadline, leaving it alone")
    return ready


def set_field(entry, name, value):
    for field in entry.get("fields", []):
        if field.get("name") == name:
            field["value"] = value
            return True
    return False


def field_value(entry, name):
    for field in entry.get("fields", []):
        if field.get("name") == name:
            return field.get("value")
    return None


def category_field(entry):
    """The download client's completed-download category field.

    Each application names it after its media type (tvCategory, movieCategory,
    musicCategory, bookCategory), each has an *ImportedCategory sibling, so the
    first plain "<something>Category" is the right one.
    """
    for field in entry.get("fields", []):
        name = field.get("name") or ""
        if name.endswith("Category") and "Imported" not in name:
            return name
    return None


def schema_entry(port, version, key, path, implementation):
    """Fetch an implementation's form template from a /schema endpoint."""
    for entry in call(port, version, key, "GET", path) or []:
        if entry.get("implementation") == implementation:
            # Deep copy: the templates are mutated before being posted back.
            return json.loads(json.dumps(entry))
    return None


def find_existing(entries, name, implementation, adopt_single=True):
    """Find the entry this module should converge rather than re-create.

    Matching has to follow the API's own rules, not ours. Prowlarr rejects a
    second application whose name matches an existing one case-INSENSITIVELY
    (the error it returns is a bare PredicateValidator on "Name"), so a
    case-sensitive comparison here means trying to re-create "sonarr" beside an
    existing "Sonarr" and collecting a 400. Fall back in two steps:

      1. exact name, then case-insensitive name - the entry the user named,
      2. failing that, the ONLY entry of the same implementation - adopt it,
         because a request front end cares that the app is registered, not what
         its label says.

    If several entries share the implementation and none carries our name,
    adopting one would be a guess about which instance is meant, so return
    nothing and let the caller warn instead.

    `adopt_single = False` disables step 2. It is used for the generic Webhook
    notification, where an unlabeled connection may well belong to something
    else entirely and silently repointing it would be worse than doing nothing.
    """
    for entry in entries:
        if (entry.get("name") or "") == name:
            return entry
    lowered = name.lower()
    for entry in entries:
        if (entry.get("name") or "").lower() == lowered:
            return entry
    if not adopt_single:
        return None
    same_kind = [entry for entry in entries if entry.get("implementation") == implementation]
    if len(same_kind) == 1:
        return same_kind[0]
    if len(same_kind) > 1:
        warn(
            f"{len(same_kind)} {implementation} entries exist and none is named "
            f"{name!r}; leaving them alone rather than guessing"
        )
    return None


def sync_download_client(name, spec, transmission):
    """Point an *arr at Transmission, converged rather than re-clicked."""
    port, version, key = spec["port"], spec["version"], spec["key"]
    template = schema_entry(port, version, key, "/downloadclient/schema", CLIENT_NAME)
    if template is None:
        warn(f"{name}: {CLIENT_NAME} is missing from the download client schema")
        return

    set_field(template, "host", transmission["host"])
    set_field(template, "port", transmission["port"])
    set_field(template, "useSsl", False)
    set_field(template, "urlBase", transmission["urlBase"])
    set_field(template, "username", "")
    set_field(template, "password", "")

    category = category_field(template)
    if category is None:
        warn(f"{name}: no download category field in the schema")
    else:
        set_field(template, category, spec["category"])

    existing = find_existing(
        call(port, version, key, "GET", "/downloadclient") or [], CLIENT_NAME, CLIENT_NAME
    )

    if existing is None:
        body = dict(template)
        body.pop("id", None)
        body.update({"name": CLIENT_NAME, "enable": True, "priority": 1, "tags": []})
        call(port, version, key, "POST", "/downloadclient", body)
        log(
            f"{name}: added the {CLIENT_NAME} download client at "
            f"{transmission['host']}:{transmission['port']}"
            f" (category {spec['category']})"
        )
        return

    managed = [field for field in ("host", "port", "urlBase", category) if field]
    drifted = [field for field in managed if field_value(existing, field) != field_value(template, field)]
    if not drifted:
        log(f"{name}: download client already correct")
        return

    body = dict(existing)
    for field in managed + ["useSsl", "username", "password"]:
        set_field(body, field, field_value(template, field))
    call(port, version, key, "PUT", f"/downloadclient/{existing['id']}", body)
    log(f"{name}: converged download client field(s): {', '.join(drifted)}")


def sync_prowlarr_application(spec, prowlarr):
    """Register an *arr with Prowlarr so indexers reach it automatically."""
    port, version, key = prowlarr["port"], prowlarr["version"], prowlarr["key"]
    implementation = spec["implementation"]
    template = schema_entry(port, version, key, "/applications/schema", implementation)
    if template is None:
        warn(f"prowlarr: no {implementation} entry in the applications schema")
        return

    set_field(template, "prowlarrUrl", f"http://127.0.0.1:{port}")
    set_field(template, "baseUrl", f"http://127.0.0.1:{spec['port']}")
    set_field(template, "apiKey", spec["key"])
    if not field_value(template, "syncCategories"):
        warn(
            f"prowlarr: the {implementation} template carries no syncCategories, "
            "so no indexers will be pushed to it - set them in the Prowlarr UI"
        )

    existing = find_existing(
        call(port, version, key, "GET", "/applications") or [], implementation, implementation
    )

    if existing is None:
        body = dict(template)
        body.pop("id", None)
        body.update({"name": implementation, "syncLevel": template.get("syncLevel") or "fullSync", "tags": []})
        call(port, version, key, "POST", "/applications", body)
        log(f"prowlarr: registered {implementation} as an application")
        return

    # Say when an existing entry is being adopted under a different label, so
    # "already registered" never hides which instance we just converged.
    existing_name = existing.get("name") or ""
    if existing_name.lower() != implementation.lower():
        log(f"prowlarr: adopting the existing {existing_name!r} entry for {implementation}")

    # apiKey is left out of the comparison: Prowlarr may hand it back masked,
    # which would otherwise look like drift on every single run.
    drifted = [
        field
        for field in ("prowlarrUrl", "baseUrl")
        if field_value(existing, field) != field_value(template, field)
    ]
    if not drifted:
        log(f"prowlarr: {existing_name or implementation} already registered")
        return

    body = dict(existing)
    for field in ("prowlarrUrl", "baseUrl", "apiKey"):
        set_field(body, field, field_value(template, field))
    call(port, version, key, "PUT", f"/applications/{existing['id']}", body)
    log(f"prowlarr: converged {existing_name or implementation} field(s): {', '.join(drifted)}")


def sync_notification(name, spec, webhook_url):
    """Point an application's failure and health events at the alert webhook.

    Without this, a download that fails to import, an indexer Cloudflare blocks
    or a download client that stops answering is only visible by opening each
    application's UI and reading its health page. Nothing is created when no
    webhook is configured, because a connection with an empty URL would just
    add a permanent health warning to the application itself.
    """
    if not webhook_url:
        log(f"{name}: ALERT_WEBHOOK_URL is unset, so notifications are skipped")
        return

    port, version, key = spec["port"], spec["version"], spec["key"]
    implementation = "Discord" if "discord" in webhook_url.lower() else "Webhook"
    template = schema_entry(port, version, key, "/notification/schema", implementation)
    if template is None:
        warn(f"{name}: no {implementation} entry in the notification schema")
        return

    # Every *arr names this field differently: Discord wants a webHookUrl,
    # everything else a url plus a method.
    field_name = "webHookUrl" if implementation == "Discord" else "url"
    if not set_field(template, field_name, webhook_url):
        warn(f"{name}: the {implementation} schema has no {field_name} field")
        return

    # Failures and health only. Grab and import events would be noise: every
    # import is already visible on the dashboard, while these three are the
    # ones that need a human.
    triggers = []
    for flag in ("onManualInteractionRequired", "onHealthIssue", "onHealthRestored"):
        if flag in template:
            template[flag] = True
            triggers.append(flag)
    if "includeHealthWarnings" in template:
        template["includeHealthWarnings"] = True
    if not triggers:
        warn(f"{name}: the {implementation} schema exposes no failure/health triggers")
        return

    # No implementation fallback for the generic Webhook: an unnamed connection
    # could belong to anything, and repointing it would be worse than skipping.
    existing = find_existing(
        call(port, version, key, "GET", "/notification") or [],
        NOTIFICATION_NAME,
        implementation,
        adopt_single=(implementation == "Discord"),
    )

    if existing is None:
        body = dict(template)
        body.pop("id", None)
        body.update({"name": NOTIFICATION_NAME, "tags": []})
        call(port, version, key, "POST", "/notification", body)
        log(f"{name}: added a {implementation} notification for failures and health")
        return

    existing_name = existing.get("name") or ""
    if existing_name.lower() != NOTIFICATION_NAME.lower():
        log(f"{name}: adopting the existing {existing_name!r} notification")

    drifted = [
        field
        for field in (field_name,)
        if field_value(existing, field) != field_value(template, field)
    ]
    missing = [flag for flag in triggers if not existing.get(flag)]
    if not drifted and not missing:
        log(f"{name}: notifications already correct")
        return

    body = dict(existing)
    set_field(body, field_name, field_value(template, field_name))
    for flag in missing:
        body[flag] = True
    call(port, version, key, "PUT", f"/notification/{existing['id']}", body)
    log(f"{name}: converged notification ({', '.join(drifted + missing)})")


def sync_indexer(prowlarr, declared, schema):
    """Converge one declared Prowlarr indexer.

    The declaration for each indexer is the set of fields Prowlarr itself
    reported, minus the `info_*` help strings, so a first run against the state
    it was exported from is a no-op - which is also what makes this safe to run
    unattended. Only indexers named here are touched; anything else the user
    added in the UI is left exactly as it is, and nothing is ever deleted.

    Cardigann definitions are looked up by `definitionName` in the indexer
    schema, which is what makes the body complete: Prowlarr expects every field
    of the definition, not just the ones being changed. The schema is fetched
    once by the caller and passed in - it lists EVERY Cardigann definition and
    is several megabytes, so fetching it per indexer would download that much
    per run for no reason.
    """
    port, version, key = prowlarr["port"], prowlarr["version"], prowlarr["key"]
    name = declared.get("name")
    definition = declared.get("definitionFile")
    if not name or not definition:
        warn("an indexer declaration is missing name or definitionFile; skipping")
        return

    template = None
    for entry in schema:
        if entry.get("definitionName") == definition and entry.get("implementation") == "Cardigann":
            template = json.loads(json.dumps(entry))
            break
    if template is None:
        warn(f"indexer {name}: no Cardigann definition named {definition!r} in the schema")
        return

    for field, value in (declared.get("fields") or {}).items():
        set_field(template, field, value)

    existing = None
    for entry in call(port, version, key, "GET", "/indexer") or []:
        if (entry.get("name") or "").lower() == name.lower():
            existing = entry
            break

    if existing is None:
        body = dict(template)
        body.pop("id", None)
        body.update(
            {
                "name": name,
                "enable": declared.get("enable", True),
                "priority": declared.get("priority", 25),
                "tags": [],
            }
        )
        call(port, version, key, "POST", "/indexer", body)
        log(f"prowlarr: added the {name} indexer ({definition})")
        return

    drifted = [
        field
        for field in (declared.get("fields") or {})
        if field_value(existing, field) != field_value(template, field)
    ]
    if not drifted:
        log(f"prowlarr: indexer {name} already correct")
        return
    body = dict(existing)
    for field in drifted:
        set_field(body, field, field_value(template, field))
    call(port, version, key, "PUT", f"/indexer/{existing['id']}", body)
    log(f"prowlarr: converged indexer {name} field(s): {', '.join(sorted(drifted))}")


def seerr_keys_asserted():
    """True once this boot has already pushed the API keys to Seerr.

    Seerr REDACTS the stored apiKey when reading its settings back, so the key
    it holds can never be compared with the one an application is using - which
    means "is this link correct?" is unanswerable for that one field. Rather
    than rewrite the link on every single run (the unit runs at boot and on a
    daily timer), this asserts the keys once per boot and then trusts Seerr:
    /run is a tmpfs, so the marker disappearing at boot is exactly the
    "once per boot" signal wanted.
    """
    return os.path.exists(SEERR_KEY_MARKER)


def mark_seerr_keys_asserted():
    try:
        os.makedirs(os.path.dirname(SEERR_KEY_MARKER), exist_ok=True)
        with open(SEERR_KEY_MARKER, "w"):
            pass
    except OSError as error:
        warn(f"seerr: could not record the key assertion ({error})")


def sync_seerr_link(service, spec, key, seerr):
    """Keep one SeerrNG service link able to reach its application.

    Patch-only, deliberately. A link is a whole settings object (import
    directory, quality profile, 4K flag, tag rules, override rules...) and
    replacing the list wholesale is how a script quietly undoes someone's
    setup. So this:

      * finds the instance by PORT, not by position,
      * uses the documented update route, PUT /settings/<service>/<id>, which
        takes a SINGLE object - POST on that path means "create", so using it
        to update would have added a duplicate instance,
      * changes only hostname, port, useSsl and apiKey,
      * never creates an instance and never deletes one,
      * leaves the profile, directory and rule choices alone: those are yours,
        and they legitimately change (Recyclarr adds profiles, for instance).
    """
    port = seerr.get("port", SEERR_PORT)
    payload = call_seerr(key, f"/api/v1/settings/{service}", port=port)
    entries = payload if isinstance(payload, list) else ((payload or {}).get(service) or [])
    target = next((entry for entry in entries if entry.get("port") == spec["port"]), None)
    if target is None:
        warn(f"seerr: no {service} instance on port {spec['port']}; add it once in the Seerr UI")
        return
    if target.get("id") is None:
        warn(f"seerr: the {service} instance has no id; skipping it")
        return

    desired = {
        "hostname": seerr.get("hostname", "127.0.0.1"),
        "port": spec["port"],
        "useSsl": False,
    }
    asserting = not seerr_keys_asserted()
    if asserting:
        desired["apiKey"] = spec["key"]

    drifted = [field for field, value in desired.items() if target.get(field) != value]
    if not drifted:
        log(f"seerr: {service} link already correct")
        return

    patched = dict(target, **desired)
    # The instance id is read-only to the API - it belongs in the URL, and
    # sending it back is rejected outright ("request/body/id is read-only"):
    # Seerr assigns it, so it is never ours to set.
    patched.pop("id", None)
    call_seerr(
        key,
        f"/api/v1/settings/{service}/{target['id']}",
        "PUT",
        patched,
        port=port,
    )
    if asserting:
        mark_seerr_keys_asserted()
    log(f"seerr: converged {service} link ({', '.join(sorted(drifted))})")


def sync_seerr(seerr, apps):
    """Converge every SeerrNG service link that this stack manages."""
    path = seerr.get("settings", SEERR_SETTINGS)
    try:
        with open(path, encoding="utf-8") as handle:
            settings = json.load(handle)
    except OSError:
        log("seerr: settings.json is not readable, skipping its service links")
        return
    key = (settings.get("main") or {}).get("apiKey")
    if not key:
        warn("seerr: no API key in its settings.json; skipping its service links")
        return
    for service in seerr.get("services", []):
        spec = apps.get(service)
        if spec is None:
            # Not running (Readarr while the ebook chain is parked), so its link
            # is left exactly as it is.
            continue
        sync_seerr_link(service, spec, key, seerr)


def sync_indexer_proxy(prowlarr, host):
    """Register FlareSolverr, so Cloudflare-protected indexers work."""
    port, version, key = prowlarr["port"], prowlarr["version"], prowlarr["key"]
    template = schema_entry(port, version, key, "/indexerproxy/schema", PROXY_NAME)
    if template is None:
        warn(f"prowlarr: {PROXY_NAME} is missing from the indexer proxy schema")
        return
    if not set_field(template, "host", host):
        warn(f"prowlarr: the {PROXY_NAME} schema has no host field")
        return

    existing = find_existing(
        call(port, version, key, "GET", "/indexerproxy") or [], PROXY_NAME, PROXY_NAME
    )

    if existing is None:
        body = dict(template)
        body.pop("id", None)
        body.update({"name": PROXY_NAME, "tags": []})
        call(port, version, key, "POST", "/indexerproxy", body)
        log(f"prowlarr: added the {PROXY_NAME} indexer proxy at {host}")
        return

    if field_value(existing, "host") == host:
        log(f"prowlarr: {PROXY_NAME} already correct")
        return

    body = dict(existing)
    set_field(body, "host", host)
    call(port, version, key, "PUT", f"/indexerproxy/{existing['id']}", body)
    log(f"prowlarr: converged {PROXY_NAME} host")


def check_root_folder(spec, wanted):
    """Report a missing root folder; creating one needs profile ids we do not
    own, so this only ever warns."""
    roots = call(spec["port"], spec["version"], spec["key"], "GET", "/rootfolder") or []
    paths = {os.path.normpath(entry.get("path", "")) for entry in roots}
    if os.path.normpath(wanted) not in paths:
        found = ", ".join(sorted(paths)) or "none"
        warn(
            f"readarr: no root folder at {wanted} (has: {found}) - add it under "
            "Settings -> Media Management"
        )
        return False
    log(f"readarr: root folder {wanted} present")
    return True


# ---------------------------------------------------------------------------
# Export mode
# ---------------------------------------------------------------------------
#
# Prowlarr's indexers and SeerrNG's service links are the last two pieces of
# this stack whose configuration exists only inside an application's database,
# and both APIs are root-only, so neither can be read while writing this. The
# safe order is therefore: export what is there now, review it, then converge
# from that as the source of truth - rather than have a convergence script
# guess at indexer field names and rewrite a working setup.
#
# This mode only ever reads. It prints a paste-ready Nix snippet with every
# field the API marks as private replaced by a marker, because those values
# have to come from a root-only file (they are per-site logins, not something
# the world-readable store may hold).

SEERR_SETTINGS = "/var/lib/seerr/settings.json"
SEERR_KEY_MARKER = "/run/servarr-sync/seerr-keys-asserted"

# Export mode is also runnable on its own (`nix run .#servarr-export`), where no
# unit environment exists, so it falls back to these. They mirror the `sites`
# list in jellyfin.nix.
EXPORT_DEFAULTS = {"prowlarr": {"port": 9696, "dir": "/var/lib/prowlarr"}}


def nix_value(value):
    """Render a Python value as a Nix literal (JSON is close enough here)."""
    return json.dumps(value)


def export_prowlarr_indexers(spec):
    key = api_key(spec["dir"])
    if key is None:
        print("# Prowlarr: no API key readable from its config directory.")
        print("# Run this as root (sudo) - the state directory is 0700.")
        return
    entries = call(spec["port"], "v1", key, "GET", "/indexer")
    if entries is None:
        print("# Prowlarr: the API did not answer; is it running?")
        return
    print(f"# {len(entries)} indexer(s) configured in Prowlarr.")
    print("# Private fields (logins, API keys) are marked <secret> and must be")
    print("# supplied from a root-only file, never from the Nix store.")
    print("indexers = [")
    for entry in sorted(entries, key=lambda e: (e.get("name") or "").lower()):
        print("  {")
        print(f"    name = {nix_value(entry.get('name'))};")
        print(f"    implementation = {nix_value(entry.get('implementation'))};")
        print(f"    priority = {entry.get('priority', 25)};")
        print(f"    enable = {str(bool(entry.get('enable'))).lower()};")
        public, private = [], []
        for field in entry.get("fields", []):
            value = field.get("value")
            name = field.get("name")
            if not name:
                continue
            if name.startswith("info_"):
                # Help text the definition renders into the form, not a setting:
                # Prowlarr fills it in itself and it changes with the definition.
                continue
            if field.get("privacy") in ("password", "apiKey", "userName"):
                private.append(name)
            elif value not in (None, "", [], {}):
                public.append(f"      {name} = {nix_value(value)};")
        if public:
            print("    fields = {")
            print("\n".join(public))
            print("    };")
        if private:
            print(f"    # secrets: {', '.join(private)}")
        print("  }")
    print("];")


def export_seerr_links():
    try:
        with open(SEERR_SETTINGS, encoding="utf-8") as handle:
            settings = json.load(handle)
    except OSError:
        print("# SeerrNG: settings.json is not readable - run this as root.")
        return
    key = (settings.get("main") or {}).get("apiKey")
    if not key:
        print("# SeerrNG: no API key in its settings.json.")
        return
    for service in ("sonarr", "radarr", "lidarr", "readarr"):
        try:
            payload = call_seerr(key, f"/api/v1/settings/{service}")
        except ApiError as error:
            print(f"# SeerrNG: {service} settings unavailable ({error})")
            continue
        if payload is None:
            print(f"# SeerrNG: {service} settings unavailable")
            continue
        # The endpoint answers with a bare list of instances; accept the
        # {service: [...]} shape too, in case a version wraps it.
        if isinstance(payload, list):
            entries = payload
        elif isinstance(payload, dict):
            entries = payload.get(service) or []
        else:
            entries = []
        print(f"# SeerrNG {service}: {len(entries)} instance(s)")
        for entry in entries:
            fields = {k: v for k, v in sorted(entry.items()) if k not in ("id", "apiKey", "tags")}
            print("  # apiKey <secret>")
            print(f"  {service} = {{ {', '.join(f'{k} = {nix_value(v)}' for k, v in fields.items())}; }};")


def call_seerr(key, path, method="GET", body=None, port=None):
    """Call SeerrNG's API, raising ApiError so a caller can react to it."""
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        f"http://127.0.0.1:{port or SEERR_PORT}{path}", data=data, method=method
    )
    request.add_header("X-Api-Key", key)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:200]
        raise ApiError(f"{method} {path} -> HTTP {error.code}: {detail}", status=error.code) from error
    except (urllib.error.URLError, OSError) as error:
        raise ApiError(f"{method} {path} -> {error}") from error
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def export(config=None):
    config = config or EXPORT_DEFAULTS
    print("# ---- Prowlarr indexers ----")
    export_prowlarr_indexers(config.get("prowlarr", EXPORT_DEFAULTS["prowlarr"]))
    print()
    print("# ---- SeerrNG service links ----")
    export_seerr_links()
    return 0


def main():
    config = load_config()
    targets = dict(config["apps"])
    polled = dict(targets)
    polled["prowlarr"] = config["prowlarr"]
    ready = wait_ready(polled, time.monotonic() + config["wait_seconds"])

    failures = 0
    webhook_url = os.environ.get("ALERT_WEBHOOK_URL", "")
    for name, spec in sorted(ready.items()):
        if name == "prowlarr":
            continue
        try:
            sync_download_client(name, spec, config["transmission"])
        except ApiError as error:
            warn(f"{name}: {error}")
            failures += 1
        try:
            sync_notification(name, spec, webhook_url)
        except ApiError as error:
            warn(f"{name}: {error}")
            failures += 1

    if "prowlarr" in ready:
        prowlarr = ready["prowlarr"]
        for name, spec in sorted(targets.items()):
            if name not in ready:
                continue
            try:
                sync_prowlarr_application(ready[name], prowlarr)
            except ApiError as error:
                warn(f"prowlarr: {name}: {error}")
                failures += 1
        declared_indexers = config.get("indexers", [])
        if declared_indexers:
            try:
                indexer_schema = call(
                    prowlarr["port"],
                    prowlarr["version"],
                    prowlarr["key"],
                    "GET",
                    "/indexer/schema",
                )
                if indexer_schema is None:
                    indexer_schema = []
            except ApiError as error:
                indexer_schema = []
                warn(f"prowlarr: could not read the indexer schema: {error}")
                failures += 1
            for declared in declared_indexers:
                try:
                    sync_indexer(prowlarr, declared, indexer_schema)
                except ApiError as error:
                    warn(f"prowlarr: indexer {declared.get('name')}: {error}")
                    failures += 1
        try:
            sync_indexer_proxy(prowlarr, config["flaresolverr_host"])
        except ApiError as error:
            warn(f"prowlarr: {error}")
            failures += 1

    if "seerr" in config:
        try:
            sync_seerr(config["seerr"], {n: s for n, s in ready.items() if n != "prowlarr"})
        except ApiError as error:
            warn(f"seerr: {error}")
            failures += 1

    root = config.get("readarr_root_folder")
    if root and "readarr" in ready:
        try:
            check_root_folder(ready["readarr"], root)
        except ApiError as error:
            warn(f"readarr: {error}")

    if failures:
        log(f"finished with {failures} failure(s)")
    else:
        log("finished, everything converged")
    return 1 if failures else 0


if __name__ == "__main__":
    if "--export" in sys.argv:
        # No unit environment when run directly from the flake, which is fine:
        # the defaults above cover the one service export needs to reach.
        configured = load_config() if os.environ.get("SERVARR_SYNC_CONFIG") else None
        sys.exit(export(configured))
    sys.exit(main())
