"""Declarative settings sync for the Servarr stack.

The NixOS configuration declares the services; this script converges the
settings that would otherwise have to be clicked in six different web UIs:

  * Prowlarr: register every *arr as an application, so Prowlarr pushes its
    indexers to them, and add FlareSolverr as an indexer proxy.
  * Sonarr/Radarr/Lidarr: add Transmission as the download client at
    the VPN namespace address, with the same per-category directory the
    tmpfiles rules already create on /Vault/Downloads.

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

import json
import os
import sys
import time

import arr_client as arr

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


# The *arr plumbing lives in arr_client - one implementation, on PYTHONPATH via
# the module that builds this script. What stays here is this script's own
# argument order, so every call site reads the way it always did.
ApiError = arr.ApiError
api_key = arr.api_key


def call(port, version, key, method, path, body=None, timeout=30):
    """This script's order (method before path); see arr_client.call."""
    return arr.call(port, version, key, path, method=method, body=body, timeout=timeout)


def probe(port, key):
    """(version, state) for a running application; see arr_client.probe_version."""
    return arr.probe_version(port, key)


def load_config():
    path = os.environ.get("SERVARR_SYNC_CONFIG")
    if not path:
        sys.exit(f"{TAG} SERVARR_SYNC_CONFIG is not set")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


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


def sync_root_folder(name, spec, path):
    """Ensure an application has `path` registered as a root folder.

    Lidarr refuses to add an artist until it has somewhere to put it, and an
    import list - the Spotify playlist that feeds the music stack - is what
    adds artists. So without a root folder pointing at the shared music
    library, Soularr has nothing to download for. Only applications that
    declare a path in the sync config are touched.

    The quality profile a NEW item gets is deliberately not set here: Sonarr
    and Radarr root folders carry no default profile at all (only Lidarr's do),
    and neither application exposes a route to update a root folder once it
    exists. That default belongs to the import list or to the application doing
    the requesting (Seerr), so it is chosen there.
    """
    if not path:
        return

    port, version, key = spec["port"], spec["version"], spec["key"]
    wanted = os.path.normpath(path)
    for folder in call(port, version, key, "GET", "/rootfolder") or []:
        if os.path.normpath(folder.get("path") or "") == wanted:
            log(f"{name}: root folder {path} already present")
            return

    # Creating one still needs both profile ids. Take the first of each rather
    # than inventing numbers; an install with no profiles cannot add anything
    # by any route anyway.
    profiles = call(port, version, key, "GET", "/qualityprofile") or []
    metadata = call(port, version, key, "GET", "/metadataprofile") or []
    if not profiles or not metadata:
        warn(f"{name}: no quality/metadata profile to attach a root folder to yet")
        return

    call(
        port,
        version,
        key,
        "POST",
        "/rootfolder",
        {
            "name": os.path.basename(wanted) or wanted,
            "path": path,
            "defaultQualityProfileId": profiles[0]["id"],
            "defaultMetadataProfileId": metadata[0]["id"],
            "defaultTags": [],
        },
    )
    log(f"{name}: added root folder {path}")


def read_secret(path):
    """The first non-empty line of a secret file, or None.

    These files are generated at activation and never enter the store, so the
    only thing that can go wrong is being asked before they exist.
    """
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                if line.strip():
                    return line.strip()
    except OSError:
        return None
    return None


# What counts as "the UI already requires a login". `forms` is what this applies;
# `basic` is accepted too, so a method chosen by hand in the UI is left alone.
LOGIN_METHODS = ("forms", "basic")


def sync_authentication(name, spec, auth):
    """Require a login for the application's web UI.

    The UI bootstrap (`/initialize.json`) hands the API key to any request the
    application considers local, and behind the reverse proxy every request
    arrives from 127.0.0.1 - so with the shipped default, which is
    `disabledForLocalAddresses`, a browser anywhere on the LAN or the Tailscale
    mesh is as good as a shell on this host, keys included. Measured before this
    existed, with no credentials at all:

        curl -H 'Host: sonarr.lan' http://127.0.0.1/initialize.json  -> key

    `authenticationRequired = enabled` is the fix, and it leaves the API alone:
    X-Api-Key bypasses the web login, so every other step in this file and the
    flake's tools keep working unchanged. Applied only while the setting is not
    already right, so a password changed in the UI later is not reverted.
    """
    port, version, key = spec["port"], spec["version"], spec["key"]
    current = call(port, version, key, "GET", "/config/host")
    if not isinstance(current, dict):
        warn(f"{name}: could not read the host configuration")
        return False
    # all() rather than a wrapped `and` chain: flake8, as the writer that builds
    # this script invokes it, rejects an operator that starts a line.
    already_secured = all(
        [
            current.get("authenticationMethod") in LOGIN_METHODS,
            current.get("authenticationRequired") == "enabled",
        ]
    )
    if already_secured:
        log(f"{name}: web UI already requires a login")
        return False

    password = read_secret(auth["password_file"])
    if not password:
        warn(f"{name}: no UI password in {auth['password_file']}, leaving the UI open")
        return False

    # The whole resource goes back, as the application's own UI does it: the
    # fields this does not name are ones it just returned.
    call(
        port,
        version,
        key,
        "PUT",
        "/config/host",
        dict(
            current,
            authenticationMethod="forms",
            authenticationRequired="enabled",
            username=auth["username"],
            password=password,
            passwordConfirmation=password,
        ),
    )

    # Read it back: a value the API rejected would otherwise leave the UI open
    # with nothing but this run's exit code to hint at it.
    after = call(port, version, key, "GET", "/config/host") or {}
    accepted = all(
        [
            after.get("authenticationMethod") in LOGIN_METHODS,
            after.get("authenticationRequired") == "enabled",
        ]
    )
    if not accepted:
        warn(
            f"{name}: still {after.get('authenticationMethod')}/"
            f"{after.get('authenticationRequired')} after the change"
        )
        return False
    log(f"{name}: web UI now requires a login as {auth['username']}")
    return True


# What each application calls the collection of things it manages. The path of
# one of them is an absolute directory recorded per item, separately from the
# root folders that contain them.
LIBRARY_RESOURCES = {
    "sonarr": "series",
    "radarr": "movie",
    "lidarr": "artist",
}


def sync_library_paths(name, spec, moves):
    """Re-point library items whose folder moved out from under them.

    A root folder and an item's own path are two different things: the root
    folder says where a library lives, and every series/movie/artist stores its
    own absolute directory beneath it. Moving the library therefore updates the
    root folder and leaves every item pointing at the directory that is gone -
    and the applications report that in a way that reads like a permissions
    problem:

        Root folder '/Vault/Jellyfin/Shows' was not found
        Access to the path '/Vault/Jellyfin/Shows/...' is denied

    The second message is systemd rather than Unix: /Vault is mounted read-only
    for these units and only the real root folders are re-opened for writing, so
    a write into the abandoned tree is refused.

    `moveFiles` is deliberately false. The files are already in their new home,
    so this is bookkeeping - asking the application to move them would fail
    against the very directory being left behind. Only items under a declared
    old prefix are touched, so a repeat run is a no-op.
    """
    resource = LIBRARY_RESOURCES.get((spec["implementation"] or "").lower())
    if resource is None or not moves:
        return

    port, version, key = spec["port"], spec["version"], spec["key"]
    repointed = 0
    for item in call(port, version, key, "GET", f"/{resource}") or []:
        path = item.get("path") or ""
        for move in moves:
            source = os.path.normpath(move["from"])
            if not (path == source or path.startswith(source + "/")):
                continue
            # The part of the path below the prefix, re-rooted under the new
            # one: /Vault/Jellyfin/Shows/X -> /Vault/Media/Shows/X.
            suffix = path[len(source) :]  # noqa: E203 - pycodestyle vs. black
            target = os.path.normpath(move["to"]) + suffix
            title = item.get("title") or item.get("artistName") or item.get("id")
            call(
                port,
                version,
                key,
                "PUT",
                f"/{resource}/{item['id']}?moveFiles=false",
                dict(item, path=target),
            )
            log(f"{name}: re-pointed {resource} {title!r} to {target}")
            repointed += 1
            break

    if repointed:
        log(f"{name}: re-pointed {repointed} item(s) left behind by the library move")
    else:
        log(f"{name}: library paths already correct")


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


def quality_profile_id(port, version, key, name):
    """The id of the quality profile called `name` in an application, or None.

    Seerr records a profile by numeric id, so the name the sync config uses has
    to be resolved against the application the link points at.
    """
    for profile in call(port, version, key, "GET", "/qualityprofile") or []:
        if profile.get("name") == name:
            return profile["id"]
    return None


# Seerr keeps its OWN copy of each application's root folder and sends it with
# every request as `rootFolderPath`, so a library move has to reach it as well.
# It did not: lib/media.nix moved /Vault/Jellyfin to /Vault/Media, servarr-sync
# re-pointed Sonarr's root folder and every series, and Seerr went on asking for
# /Vault/Jellyfin/Shows until Sonarr answered
#
#   RootFolderPath: Root folder '/Vault/Jellyfin/Shows' does not exist
#
# and the request was marked FAILED - while this file reported "sonarr link
# already correct", because the root folder was not a field it managed.
#
# A root folder the application really has is left exactly as it is: pointing
# anime requests at a separate "Anime" root folder is a choice, not drift. Only
# a copy of a folder the application no longer has is replaced, and only when
# the replacement is unambiguous.
DIRECTORY_SUFFIX = "Directory"


def seerr_directory_fixes(target, spec, declared):
    """The link's root-folder fields that need a different path, for the caller.

    Every field whose name ends in `Directory` and whose value is an absolute
    path is one of these copies: `activeDirectory` for everything, plus
    `activeAnimeDirectory`/`active4kDirectory` and their anime variants where
    the application has them. A value the application does not have as a root
    folder can only produce a 400, so it is worth converging whatever it says.

    The replacement is the root folder this repository declares for the
    application when the application really has it, otherwise the application's
    only root folder. With several candidates and no declaration, which one is
    meant is a guess - warn and leave them alone.
    """
    fields = [
        (name, value)
        for name, value in target.items()
        if name.endswith(DIRECTORY_SUFFIX) and isinstance(value, str) and value.startswith("/")
    ]
    if not fields:
        return {}

    port, version, key = spec["port"], spec["version"], spec["key"]
    valid = {
        os.path.normpath(folder.get("path") or "")
        for folder in call(port, version, key, "GET", "/rootfolder") or []
    }
    stale = [(name, value) for name, value in fields if os.path.normpath(value) not in valid]
    if not stale:
        return {}

    if declared and os.path.normpath(declared) in valid:
        replacement = declared
    elif len(valid) == 1:
        replacement = next(iter(valid))
    else:
        warn(
            f"seerr: {', '.join(name for name, _ in stale)} name root folder(s) the "
            f"application does not have, and it offers {len(valid)} to choose from; "
            f"leaving them alone"
        )
        return {}

    for name, value in stale:
        log(f"seerr: {name} points at {value}, which is gone; using {replacement}")
    return {name: replacement for name, _ in stale}


def sync_seerr_link(service, spec, key, seerr, asserting, declared_root=None):
    """Keep one SeerrNG service link able to reach its application.

    Returns True when the link was actually patched, so the caller knows whether
    the apiKey assertion it authorized was carried out.

    Patch-only, deliberately. A link is a whole settings object (import
    directory, quality profile, 4K flag, tag rules, override rules...) and
    replacing the list wholesale is how a script quietly undoes someone's
    setup. So this:

      * finds the instance by PORT, not by position,
      * uses the documented update route, PUT /settings/<service>/<id>, which
        takes a SINGLE object - POST on that path means "create", so using it
        to update would have added a duplicate instance,
      * changes only hostname, port, useSsl, apiKey, the root folder(s) it sends
        and the quality profile named below,
      * never creates an instance and never deletes one,
      * converges the quality profile ONLY when the sync config names one for
        this service, and only through a field the link already exposes. This
        is the one place a "default profile for new items" really lives for
        Sonarr and Radarr: their own root folders carry no such field, so the
        requesting application is what decides. The import directory, 4K flag
        and rule choices are still left alone - those are yours.

    The root folder is converged only when it names something the application
    does not have (see seerr_directory_fixes): a stale copy is a request that
    cannot succeed, while a valid one is a decision this file has no business
    second-guessing.
    """
    port = seerr.get("port", SEERR_PORT)
    payload = call_seerr(key, f"/api/v1/settings/{service}", port=port)
    entries = payload if isinstance(payload, list) else ((payload or {}).get(service) or [])
    target = next((entry for entry in entries if entry.get("port") == spec["port"]), None)
    if target is None:
        warn(f"seerr: no {service} instance on port {spec['port']}; add it once in the Seerr UI")
        return False
    if target.get("id") is None:
        warn(f"seerr: the {service} instance has no id; skipping it")
        return False

    desired = {
        "hostname": seerr.get("hostname", "127.0.0.1"),
        "port": spec["port"],
        "useSsl": False,
    }

    # The profile SeerrNG asks for when it creates an item here. Only a field
    # the link already exposes is touched, so an upstream rename is skipped with
    # a warning rather than sent back as an unknown property.
    wanted = (seerr.get("quality_profiles") or {}).get(service)
    if wanted:
        id_field = next((f for f in ("activeProfileId", "profileId") if f in target), None)
        name_field = next((f for f in ("activeProfileName", "profileName") if f in target), None)
        profile_id = quality_profile_id(spec["port"], spec["version"], spec["key"], wanted)
        if profile_id is None:
            warn(
                f"seerr: {service} has no quality profile named {wanted!r} yet; "
                f"leaving its profile alone"
            )
        elif id_field is None:
            warn(f"seerr: {service} link exposes no profile field; leaving its profile alone")
        else:
            desired[id_field] = profile_id
            if name_field:
                desired[name_field] = wanted

    # A root folder the application no longer has is a request that cannot
    # succeed, so it is converged whatever the rest of the link says.
    for field, value in seerr_directory_fixes(target, spec, declared_root).items():
        desired[field] = value

    # `asserting` is a parameter, not a call made here: the marker it reflects is
    # per BOOT. Read inside this per-link function, the first link that drifted
    # set it and the links after it in the same run saw False, so they left their
    # own key stale until the next boot.
    if asserting:
        desired["apiKey"] = spec["key"]

    drifted = [field for field, value in desired.items() if target.get(field) != value]
    if not drifted:
        log(f"seerr: {service} link already correct")
        return False

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
    # The key assertion is the caller's to mark, once per boot for every link.
    log(f"seerr: converged {service} link ({', '.join(sorted(drifted))})")
    return True


def sync_seerr(seerr, apps, root_folders=None):
    """Converge every SeerrNG service link that this stack manages."""
    root_folders = root_folders or {}
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
    # Assert the keys once per boot: read the marker before the loop and write it
    # after, so every link in this run gets its apiKey pushed. All three apps are
    # configured, so a marker written by the first drifting link used to leave the
    # other two unasserted.
    asserting = not seerr_keys_asserted()
    converged = False
    for service in seerr.get("services", []):
        spec = apps.get(service)
        if spec is None:
            # A service SeerrNG knows about but this stack does not run (a link
            # left over from a removed application, say), so its link is left
            # exactly as it is.
            continue
        converged = sync_seerr_link(
            service, spec, key, seerr, asserting, root_folders.get(service)
        ) or converged

    if asserting and converged:
        mark_seerr_keys_asserted()


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
# unit environment exists, so it falls back to these. They mirror the
# `device.media.services` registry (system/server/media/options.nix).
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
    for service in ("sonarr", "radarr", "lidarr"):
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
    """Call SeerrNG's API, raising ApiError so a caller can react to it.

    Callers pass Seerr's full path ("/api/v1/settings/sonarr"); arr_client builds
    the version segment, so it is stripped here rather than at every call site.
    """
    return arr.call(
        port or SEERR_PORT,
        "v1",
        key,
        path.removeprefix("/api/v1"),
        method=method,
        body=body,
        timeout=15,
    )


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

    # Before the rest, because it is the only step whose absence is a security
    # hole: a browser that reaches one of these web UIs can read its API key.
    authentication = config.get("authentication")
    if authentication:
        for name, spec in sorted(ready.items()):
            try:
                sync_authentication(name, spec, authentication)
            except ApiError as error:
                warn(f"{name}: {error}")
                failures += 1

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

    # Root folders are what let an application add anything at all; whichever
    # ones a stack declares are the ones touched.
    for name, path in config.get("root_folders", {}).items():
        if name not in ready:
            continue
        try:
            sync_root_folder(name, ready[name], path)
        except ApiError as error:
            warn(f"{name}: root folder: {error}")
            failures += 1

    # After the root folders, never before: an item can only be re-pointed at a
    # directory the application already accepts as a library.
    for name, moves in config.get("library_moves", {}).items():
        if name not in ready:
            continue
        try:
            sync_library_paths(name, ready[name], moves)
        except ApiError as error:
            warn(f"{name}: library paths: {error}")
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
            sync_seerr(
                config["seerr"],
                {n: s for n, s in ready.items() if n != "prowlarr"},
                config.get("root_folders", {}),
            )
        except ApiError as error:
            warn(f"seerr: {error}")
            failures += 1

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
