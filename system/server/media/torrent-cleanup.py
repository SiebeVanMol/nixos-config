"""Remove torrents that have stalled for good, then ask the application that
wanted them to search again.

Transmission never gives up on a torrent, and the *arr applications do not treat
"stalled with no peers" as a failure - a download only becomes "failed" when the
client says so. So a dead torrent sits in .incomplete forever, holding disk
space and occupying the queue while Sonarr/Radarr/Lidarr wait on something that
will never arrive. This sweeps those out and triggers a fresh search for the
exact episode, movie or album that was being downloaded.

What it refuses to touch:
  * torrents that are complete (or seeding) - those are someone else's job;
  * torrents that are merely slow - a candidate must be stalled *now* and have
    had no activity for the threshold, so a torrent that moved an hour ago is
    left alone however quiet it looks at this instant.

The replacement search is matched by torrent hash against each application's own
queue *before* the removal, so it re-searches that one item rather than
triggering a whole-library sweep.

Configuration arrives as JSON through TORRENT_CLEANUP_CONFIG (or --config); see
torrent-cleanup.nix. Run with --dry-run to see what it would do.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

import arr_client as arr

TAG = "[torrent-cleanup]"

FIELDS = [
    "hashString",
    "name",
    "status",
    "percentDone",
    "isStalled",
    "trackerStats",
    "activityDate",
    "addedDate",
    "downloadDir",
    "totalSize",
]


def log(message):
    print(f"{TAG} {message}", flush=True)


def load_config():
    path = None
    if "--config" in sys.argv:
        path = sys.argv[sys.argv.index("--config") + 1]
    path = path or os.environ.get("TORRENT_CLEANUP_CONFIG")
    if not path:
        sys.exit(f"{TAG} TORRENT_CLEANUP_CONFIG is not set")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


# The *arr plumbing lives in arr_client. http_json stays, because this script
# also polls a download client's queue, which is not an *arr API at all.
api_key = arr.api_key


def api_version(port, key):
    """v3 for Sonarr/Radarr, v1 for Lidarr; see arr_client.probe_version."""
    version, _state = arr.probe_version(port, key)
    return version


def http_json(url, key=None, method="GET", body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Accept", "application/json")
    if key:
        request.add_header("X-Api-Key", key)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read()
    return json.loads(raw) if raw else None


class Transmission:
    def __init__(self, url):
        self.url = url
        self.session = None

    def call(self, method, arguments=None):
        data = json.dumps({"method": method, "arguments": arguments or {}}).encode()
        request = urllib.request.Request(self.url, data=data, method="POST")
        request.add_header("Content-Type", "application/json")
        if self.session:
            request.add_header("X-Transmission-Session-Id", self.session)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as error:
            # Transmission answers the first request with 409 and the session id
            # it expects; every client has to do this dance.
            if error.code != 409:
                raise
            self.session = error.headers.get("X-Transmission-Session-Id")
            if not self.session:
                raise
            return self.call(method, arguments)


def seeder_count(torrent):
    counts = [t.get("seederCount", -1) for t in (torrent.get("trackerStats") or [])]
    return max(counts, default=-1)


def stalled(torrent, days, now):
    if not torrent.get("isStalled"):
        return None
    percent = torrent.get("percentDone") or 0.0
    if percent >= 1.0:
        return None
    last = max(torrent.get("activityDate") or 0, torrent.get("addedDate") or 0)
    age = (now - last) / 86400 if last else 0.0
    if age < days:
        return None
    return {
        "hash": (torrent.get("hashString") or "").lower(),
        "name": torrent.get("name") or "",
        "percent": percent * 100,
        "seeders": seeder_count(torrent),
        "age": age,
        "size": torrent.get("totalSize") or 0,
        "category": os.path.basename((torrent.get("downloadDir") or "").rstrip("/")),
    }


def queue_url(spec):
    kind = spec["kind"]
    base = f"http://127.0.0.1:{spec['port']}/api/{spec['version']}/queue?page=1&pageSize=250"
    if kind == "sonarr":
        return base + "&includeUnknownSeriesItems=true"
    if kind == "radarr":
        return base + "&includeUnknownMovieItems=true"
    if kind == "lidarr":
        return base + "&includeUnknownArtistItems=true&includeUnknownAlbumItems=true"
    return None


def search_body(kind, record):
    """The command that makes an application look for a replacement."""
    if kind == "sonarr":
        if record.get("episodeId"):
            return {"name": "EpisodeSearch", "episodeIds": [record["episodeId"]]}
        if record.get("seriesId") is not None and record.get("seasonNumber") is not None:
            return {
                "name": "SeasonSearch",
                "seriesId": record["seriesId"],
                "seasonNumber": record["seasonNumber"],
            }
    elif kind == "radarr":
        if record.get("movieId"):
            return {"name": "MoviesSearch", "movieIds": [record["movieId"]]}
    elif kind == "lidarr":
        if record.get("albumId"):
            return {"name": "AlbumSearch", "albumIds": [record["albumId"]]}
        if record.get("artistId"):
            return {"name": "ArtistSearch", "artistIds": [record["artistId"]]}
    return None


def resolve_apps(apps):
    resolved = {}
    for name, spec in sorted(apps.items()):
        key = api_key(spec["dir"])
        if key is None:
            log(f"{name}: no readable API key yet, skipping")
            continue
        version = api_version(spec["port"], key)
        if version is None:
            log(f"{name}: not answering, skipping")
            continue
        resolved[name] = {**spec, "key": key, "version": version, "kind": spec["implementation"].lower()}
    return resolved


def collect_queue_targets(resolved):
    """hash -> (app name, search command), read before anything is removed."""
    targets = {}
    for name, spec in resolved.items():
        try:
            records = http_json(queue_url(spec), spec["key"]).get("records", [])
        except (urllib.error.URLError, OSError, ValueError) as error:
            log(f"{name}: could not read the queue: {error}")
            continue
        for record in records:
            digest = (record.get("downloadId") or "").lower()
            body = search_body(spec["kind"], record)
            if digest and body:
                targets[digest] = (name, body)
    return targets


def main():
    dry_run = "--dry-run" in sys.argv
    config = load_config()
    days = float(config["stalled_days"])

    resolved = resolve_apps(config["apps"])
    category_to_app = {spec["category"]: name for name, spec in resolved.items()}

    transmission = Transmission(config["transmission"]["url"])
    try:
        torrents = transmission.call("torrent-get", {"fields": FIELDS})["arguments"]["torrents"]
    except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
        log(f"Transmission is not answering ({error}); leaving it alone")
        return 0

    now = time.time()
    candidates = [c for t in torrents if (c := stalled(t, days, now))]
    if not candidates:
        log(f"no torrent stalled for more than {days:g} day(s)")
        return 0

    targets = collect_queue_targets(resolved)

    searches = {}
    for candidate in candidates:
        app = category_to_app.get(candidate["category"])
        target = targets.get(candidate["hash"])
        if target:
            searches.setdefault(target[0], []).append(target[1])
        origin = app or "not from an *arr app"
        log(
            f"{'would remove' if dry_run else 'removing'} {candidate['hash'][:8]} "
            f"{candidate['name'][:64]} ({candidate['percent']:.0f}%, "
            f"{candidate['seeders']} seeder(s), idle {candidate['age']:.1f}d, "
            f"{candidate['size'] / 1024 ** 2:.0f} MiB) [{origin}]"
        )
        if not dry_run:
            transmission.call(
                "torrent-remove",
                {"ids": [candidate["hash"]], "delete-local-data": True},
            )

    for name, bodies in searches.items():
        spec = resolved[name]
        for body in bodies:
            log(f"{name}: searching again ({body['name']})")
            if dry_run:
                continue
            try:
                http_json(
                    f"http://127.0.0.1:{spec['port']}/api/{spec['version']}/command",
                    spec["key"],
                    "POST",
                    body,
                )
            except (urllib.error.URLError, OSError, ValueError) as error:
                log(f"{name}: replacement search failed: {error}")

    verb = "would remove" if dry_run else "removed"
    log(
        f"{verb} {len(candidates)} torrent(s); "
        f"{'would trigger' if dry_run else 'triggered'} "
        f"{sum(len(b) for b in searches.values())} replacement search(es)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
