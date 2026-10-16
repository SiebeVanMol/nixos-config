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

The API key handling and the call plumbing come from arr_client, the shared
module every media script imports - the module that builds this one puts it on
PYTHONPATH (lib/arr-client.nix). What stays here is the policy: every API failure
is swallowed, because a sick *arr must not make the health check look broken.
"""

import json
import os
import sys

import arr_client as arr


def load_apps():
    """Which applications to check, and where each of them listens.

    ARR_HEALTH_CONFIG is a JSON written by the module that builds this script,
    from the live registry - so a host that moved a port is still reported on at
    the new number. There is deliberately no built-in list: that was a second
    copy of those ports, and the copy is the thing that goes stale.
    """
    path = os.environ.get("ARR_HEALTH_CONFIG")
    if not path:
        print("arr-health: ARR_HEALTH_CONFIG is not set - nothing to check", file=sys.stderr)
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)["apps"]


api_key = arr.api_key


def call(port, version, key, path, timeout=10):
    """The decoded body, or None on ANY failure.

    This script reports, it does not judge: a failing *arr must not make the
    health check itself look broken.
    """
    try:
        return arr.call(port, version, key, path, timeout=timeout)
    except arr.ApiError:
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
    apps = load_apps()
    if apps is None:
        return 1
    lines = []
    for app, spec in sorted(apps.items()):
        if not os.path.isdir(spec["dir"]):
            continue
        lines += health(app, spec)
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
