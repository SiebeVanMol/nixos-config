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


def find_existing(entries, name, implementation):
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
    """
    for entry in entries:
        if (entry.get("name") or "") == name:
            return entry
    lowered = name.lower()
    for entry in entries:
        if (entry.get("name") or "").lower() == lowered:
            return entry
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


def main():
    config = load_config()
    targets = dict(config["apps"])
    polled = dict(targets)
    polled["prowlarr"] = config["prowlarr"]
    ready = wait_ready(polled, time.monotonic() + config["wait_seconds"])

    failures = 0
    for name, spec in sorted(ready.items()):
        if name == "prowlarr":
            continue
        try:
            sync_download_client(name, spec, config["transmission"])
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
        try:
            sync_indexer_proxy(prowlarr, config["flaresolverr_host"])
        except ApiError as error:
            warn(f"prowlarr: {error}")
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
    sys.exit(main())
