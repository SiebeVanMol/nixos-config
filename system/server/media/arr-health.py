"""Report the health warnings the *arr services report about themselves.

Each application already knows what is wrong with it - an indexer that started
returning 403s, a download client that went away, a root folder that is not
writable - and publishes it on /api/<v>/health. Reading it once a day means
those problems surface in the host health check instead of waiting for someone
to open four different web UIs and look at the corner of the screen.

Output is one line per finding, prefixed with the application name, and the
caller decides what to do with it. This script always exits 0: it reports, it
does not judge, and a failing *arr must not make the health check itself look
broken.

The API key handling deliberately mirrors servarr-sync.py rather than importing
it: these are two small standalone scripts in the store, and a shared module
would have to be built and referenced by both. The duplication is ~30 lines of
call plumbing.
"""

import glob
import json
import os
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

# Same ports as the `sites` list in jellyfin.nix, minus the ones that need no
# health check of their own.
APPS = {
    "sonarr": {"port": 8989, "dir": "/var/lib/sonarr"},
    "radarr": {"port": 7878, "dir": "/var/lib/radarr"},
    "lidarr": {"port": 8686, "dir": "/var/lib/lidarr"},
    "prowlarr": {"port": 9696, "dir": "/var/lib/prowlarr"},
}


def api_key(app_dir):
    """Read an application's API key from its own config.xml.

    Both layouts are tried: Prowlarr keeps config.xml directly in its data
    directory, the others one level down under .config/<Project>.
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


def call(port, version, key, path, timeout=10):
    request = urllib.request.Request(f"http://127.0.0.1:{port}/api/{version}{path}")
    request.add_header("X-Api-Key", key)
    request.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read() or b"null")
    except (urllib.error.URLError, OSError, json.JSONDecodeError):
        return None


def health(app, spec):
    """Return the findings for one application, as printable lines."""
    key = api_key(spec["dir"])
    if key is None:
        # Either it has not started yet or its config is not readable; either
        # way there is nothing to report and it is not an error worth a line.
        return []
    for version in ("v3", "v1"):
        entries = call(spec["port"], version, key, "/health")
        if entries is None:
            continue
        if not isinstance(entries, list):
            return []
        lines = []
        for entry in entries:
            kind = (entry.get("type") or "warning").lower()
            message = " ".join((entry.get("message") or "").split())
            if message:
                lines.append(f"{app} reports {kind}: {message}")
        return lines
    return []


def main():
    lines = []
    for app, spec in sorted(APPS.items()):
        if not os.path.isdir(spec["dir"]):
            continue
        lines += health(app, spec)
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
