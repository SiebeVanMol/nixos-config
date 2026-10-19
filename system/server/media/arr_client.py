"""The *arr API plumbing the media scripts share.

Six scripts read an application's API key out of its own config.xml, call the
API on loopback, and work out which API version answers. Every one of them had
its own copy of that plumbing, so a fix to a timeout, a header or an error path
was six edits in six files that nothing checked - and the copies had already
drifted (one had lost the JSON-decode guard the others had, one raised on a
malformed body where another returned None).

What each script keeps is its own *signature*, because the call conventions
genuinely differ - servarr-sync puts the method before the path, servarr-sweep
takes query parameters and a long timeout for a full-library sweep, media-recode
defaults the method from the body, arr-health must never raise. Those become
thin delegations ("shared plumbing lives in arr_client"), and the implementations
live here once.

Delivered on PYTHONPATH: each module that builds one of these scripts passes
`--set PYTHONPATH ${arrClient}` to the wrapper (lib/arr-client.nix), so the
scripts stay standalone files in the store and `import arr_client` still works.
"""

import glob
import json
import os
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

#: Default for a call that returns a body. A full-library sweep wants longer
#: (it asks for every episode of every series) and a probe wants much less.
DEFAULT_TIMEOUT = 30
PROBE_TIMEOUT = 5

#: How long to keep retrying a *refused* connection. A rebuild restarts the
#: applications these scripts converge, and a timer can fire inside that window:
#: the switch stops seerr for a second, the call fails with ECONNREFUSED, and
#: `nixos-rebuild` reports the whole switch as failed (exit 4) because a unit the
#: timer started had failed. Fifteen seconds covers a restart - and nothing else,
#: so a genuinely stopped application still fails the run and still gets noticed.
#: An HTTP answer is never retried: that is a reply, not a pause.
RETRY_SECONDS = 15.0
RETRY_DELAY = 1.0

#: How much of an error body to quote. The *arr APIs answer a validation failure
#: with a JSON body far longer than anyone reads in a log line.
DETAIL_CHARS = 600


class ApiError(Exception):
    """An API call that could not be completed.

    `status` is the HTTP status when the server answered at all. A 401 proves the
    application is up and rejected the key, which is a different problem from a
    connection that was refused - one is a config to fix, the other is a service
    to wait for.
    """

    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


def api_key(app_dir):
    """The API key an application wrote into its own config.xml, or None.

    Where that file lives depends on how the service was started, so both
    layouts are tried: Prowlarr is launched with -data=/var/lib/prowlarr and
    keeps config.xml directly in that directory, while Sonarr, Radarr and Lidarr
    are launched with -data=/var/lib/<app>/.config/<Project> and keep it one
    level further down. Getting this wrong is not a soft failure - the caller
    then waits for an application that never looks ready, or writes an instance
    with no usable key.
    """
    candidates = [os.path.join(app_dir, "config.xml")]
    candidates += sorted(glob.glob(os.path.join(app_dir, ".config", "*", "config.xml")))
    for path in candidates:
        try:
            root = ET.parse(path).getroot()
        except (OSError, ET.ParseError):
            continue
        node = root.find("ApiKey")
        found = (node.text or "").strip() if node is not None else ""
        if found:
            return found
    return None


def describe_error(detail):
    """Turn an *arr error body into one readable line.

    The APIs answer a validation failure with a JSON body carrying a message and
    often a field name; anything else is collapsed whitespace.
    """
    detail = (detail or "").strip()
    if not detail:
        return ""
    try:
        payload = json.loads(detail)
    except json.JSONDecodeError:
        return " ".join(detail.split())[:200]
    parts = []
    for item in payload if isinstance(payload, list) else [payload]:
        if not isinstance(item, dict):
            continue
        message = item.get("errorMessage") or item.get("message") or ""
        placeholders = item.get("formattedMessagePlaceholderValues") or {}
        prop = placeholders.get("PropertyName")
        value = placeholders.get("PropertyValue") or placeholders.get("AttemptedValue")
        if prop:
            message = f"{message} [{prop}={value}]" if message else f"[{prop}={value}]"
        if message:
            parts.append(message.strip())
    return "; ".join(parts)[:300] if parts else " ".join(detail.split())[:200]


def call(
    port,
    version,
    key,
    path,
    method=None,
    body=None,
    params=None,
    timeout=DEFAULT_TIMEOUT,
    retry_seconds=RETRY_SECONDS,
):
    """Call one of the *arr APIs on loopback and return the decoded body.

    `method` defaults to POST when there is a body and GET otherwise, which is
    what every media script wants and what two of them implemented by hand.
    Raises ApiError, with `status` set when the server answered.

    A refused connection is retried for `retry_seconds` (see RETRY_SECONDS) and
    then given up on; `probe_version` opts out with 0, because its poll loop is
    the thing that decides how long to wait, and a probe that blocks for fifteen
    seconds per application would turn one slow boot into a five-minute one.
    """
    url = f"http://127.0.0.1:{port}/api/{version}{path}"
    if params:
        url += "?" + "&".join(f"{name}={value}" for name, value in params.items())
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method or ("POST" if data else "GET"))
    request.add_header("X-Api-Key", key)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    deadline = time.monotonic() + retry_seconds
    while True:
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
            break
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:DETAIL_CHARS]
            raise ApiError(
                f"{method or 'GET'} {path} -> HTTP {error.code}: {describe_error(detail)}",
                status=error.code,
            ) from error
        except (urllib.error.URLError, OSError) as error:
            if _restarting(error) and time.monotonic() < deadline:
                time.sleep(RETRY_DELAY)
                continue
            raise ApiError(f"{method or 'GET'} {path} -> {error}") from error
    return decode(raw, path)


def _restarting(error):
    """True when the failure looks like "the service is restarting".

    urllib wraps a refused connection in URLError whose `reason` is the original
    OSError, so both shapes are checked. Anything else - a DNS failure, a 401, a
    timeout mid-response - is not a restart and is not retried.
    """
    if isinstance(error, (ConnectionRefusedError, ConnectionResetError, TimeoutError)):
        return True
    reason = getattr(error, "reason", None)
    return isinstance(reason, (ConnectionRefusedError, ConnectionResetError, TimeoutError))


def decode(raw, path=""):
    """Decode a response body, refusing to guess at one that is not JSON."""
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ApiError(f"unparseable response from {path or 'the API'}") from error


def probe_version(port, key, timeout=PROBE_TIMEOUT):
    """Classify a running application as (version, state).

    Sonarr and Radarr answer on v3 while Lidarr and Prowlarr answer on v1, so
    probing removes the need to hardcode that per application. `state` is "ok"
    (it answered and accepted the key), "unauthorized" (it answered but rejected
    the key - a config problem that waiting cannot fix) or "down" (nothing
    answered yet).
    """
    saw_response = False
    for version in ("v3", "v1"):
        try:
            call(port, version, key, "/system/status", timeout=timeout, retry_seconds=0)
            return version, "ok"
        except ApiError as error:
            if error.status is not None:
                saw_response = True
    return None, "unauthorized" if saw_response else "down"
