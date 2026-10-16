"""One-off, paced "go and find better rips" sweep across the *arr library.

Houndarr is the long-term answer, and it already does exactly this search: its
upgrade pass walks the whole library, and its cutoff pass covers everything
sitting below the quality profile. What it will not do is hurry. The engine
clamps the upgrade pass to five searches an hour per instance no matter what the
database says (``_UPGRADE_HOURLY_CAP_HARD_CAP`` / ``_UPGRADE_BATCH_HARD_CAP``,
both 5), which is a deliberate protection for the indexers rather than a
configuration mistake - so a first pass over a few hundred items takes days.

This is the "do it now" counterpart. It asks each application for the items it
already holds a file for, and issues the search commands itself at a pace the
operator picks. It changes nothing else: every application still decides what to
grab from its quality profile and custom format scores, exactly as it does for a
search Houndarr triggers. Nothing here replaces Houndarr - it front-loads the
backlog so the slow, safe sweep only has to keep up afterwards.

The pacing is the entire point of the file. One search reaches every indexer
enabled in Prowlarr, and the public trackers in that list rate-limit, return
empty results, and eventually ban a client that fires thousands of searches at
once. ``--delay`` is the gap between one command and the next and defaults to
something unhurried; lower it only if the indexers stay happy.

Dry run by default: it prints the plan, with counts and an estimate, and sends
nothing until ``--apply`` is given.

    sudo nix run .#servarr-sweep                     # what would happen
    sudo nix run .#servarr-sweep -- --apply          # do it, one per 10s
    sudo nix run .#servarr-sweep -- --apply --delay 3 --app radarr

Root is required for the same reason as the other *arr helpers: the API key
lives in a 0700 config.xml inside each application's state directory.
"""

import argparse
import json
import os
import sys
import time

import arr_client as arr

# Fallbacks for a standalone `nix run`, mirroring the registry in
# system/server/media. A SERVARR_SWEEP_CONFIG JSON overrides them, which is what
# the NixOS module would pass if this ever grows a scheduled form.
DEFAULT_APPS = {
    "sonarr": {"port": 8989, "dir": "/var/lib/sonarr", "version": "v3"},
    "radarr": {"port": 7878, "dir": "/var/lib/radarr", "version": "v3"},
    "lidarr": {"port": 8686, "dir": "/var/lib/lidarr", "version": "v1"},
}

PAGE_SIZE = 250


def log(message):
    print(message, flush=True)


def warn(message):
    print(f"WARNING: {message}", file=sys.stderr, flush=True)


# The *arr plumbing lives in arr_client; what stays here is this script's own
# conventions - a sweep asks for every episode of every series, so it wants a
# much longer timeout than the default.
ApiError = arr.ApiError
api_key = arr.api_key


def call(port, version, key, path, params=None, body=None, timeout=120, method=None):
    return arr.call(
        port, version, key, path, method=method, body=body, params=params, timeout=timeout
    )


def load_apps():
    path = os.environ.get("SERVARR_SWEEP_CONFIG")
    if not path:
        return dict(DEFAULT_APPS)
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)["apps"]


def plan_radarr(port, version, key, _args):
    """One MoviesSearch per film that already has a file."""
    movies = call(port, version, key, "/movie") or []
    commands = []
    for movie in sorted(movies, key=lambda m: m.get("sortTitle") or ""):
        if not movie.get("hasFile"):
            continue
        # A command per film rather than one command carrying every id: the
        # delay between commands is the only rate control there is, and a single
        # bulk command would hand the application all of them at once.
        commands.append(
            (
                f"{movie.get('title')} ({movie.get('year')})",
                {"name": "MoviesSearch", "movieIds": [movie["id"]]},
            )
        )
    return commands


def plan_sonarr(port, version, key, args):
    """One search per season that has a file, or per episode if asked.

    Season by default because that is how a batch release is found: an episode
    search answers "is there a better rip of this episode", a season search also
    lets Sonarr pick up a whole-season pack, which is where the HEVC/AV1 re-rips
    of an older series usually are.
    """
    commands = []
    for series in sorted(call(port, version, key, "/series") or [], key=lambda s: s.get("title") or ""):
        episodes = call(
            port,
            version,
            key,
            "/episode",
            params={"seriesId": series["id"], "includeEpisodeFile": "true"},
        )
        episodes = episodes or []
        if args.sonarr_mode == "episode":
            for episode in episodes:
                if not episode.get("hasFile"):
                    continue
                label = (
                    f"{series.get('title')} S{episode.get('seasonNumber', 0):02d}"
                    f"E{episode.get('episodeNumber', 0):02d}"
                )
                commands.append(
                    (label, {"name": "EpisodeSearch", "episodeIds": [episode["id"]]})
                )
            continue

        seasons = sorted({e.get("seasonNumber", 0) for e in episodes if e.get("hasFile")})
        for season in seasons:
            label = f"{series.get('title')} season {season}"
            commands.append(
                (
                    label,
                    {
                        "name": "SeasonSearch",
                        "seriesId": series["id"],
                        "seasonNumber": season,
                    },
                )
            )
    return commands


def plan_lidarr(port, version, key, _args):
    """One AlbumSearch per album that already has at least one track file."""
    commands = []
    for artist in sorted(call(port, version, key, "/artist") or [], key=lambda a: a.get("artistName") or ""):
        albums = call(port, version, key, "/album", params={"artistId": artist["id"]}) or []
        for album in albums:
            stats = album.get("statistics") or {}
            if not (stats.get("trackFileCount") or 0):
                continue
            commands.append(
                (
                    f"{artist.get('artistName')} - {album.get('title')}",
                    {"name": "AlbumSearch", "albumIds": [album["id"]]},
                )
            )
    return commands


PLANNERS = {
    "sonarr": plan_sonarr,
    "radarr": plan_radarr,
    "lidarr": plan_lidarr,
}


def human_duration(seconds):
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m {seconds % 60}s"
    return f"{seconds // 3600}h {(seconds % 3600) // 60}m"


def build_plan(name, spec, args):
    key = api_key(spec["dir"])
    if key is None:
        warn(f"{name}: no API key readable from {spec['dir']} (run this as root)")
        return None, []
    planner = PLANNERS.get(name)
    if planner is None:
        warn(f"{name}: no planner for this application; skipping it")
        return None, []
    commands = planner(spec["port"], spec["version"], key, args)
    return key, commands


# How each application lists the files it holds, and how one is deleted. The
# delete goes through the API rather than `rm` on purpose: the application then
# knows the item is missing and monitored again and searches for it. Removing
# the file behind its back would leave it believing it still had something.
FILE_ENDPOINTS = {
    "radarr": {"items": "/movie", "delete": "/moviefile"},
    "sonarr": {"items": "/series", "list": "/episodefile", "by": "seriesId",
               "delete": "/episodefile"},
    "lidarr": {"items": "/artist", "list": "/trackfile", "by": "artistId",
               "delete": "/trackfile"},
}


def quality_name(entry):
    """The recorded quality name, e.g. 'Bluray-2160p Remux'."""
    quality = (entry.get("quality") or {}).get("quality") or {}
    return quality.get("name") or ""


def files_for(name, spec, key, item):
    """The files an application holds for one item."""
    endpoint = FILE_ENDPOINTS.get(name)
    if endpoint is None:
        return []
    if name == "radarr":
        # Radarr embeds the file in the movie resource.
        found = item.get("movieFile")
        return [found] if found else []
    return call(
        spec["port"], spec["version"], key, endpoint["list"],
        params={endpoint["by"]: item["id"]},
    ) or []


def purge_app(name, spec, args):
    """Delete the files of one application whose quality matches --purge-quality."""
    key = api_key(spec["dir"])
    if key is None:
        warn(f"{name}: no API key readable from {spec['dir']} (run this as root)")
        return 0, 0

    needle = args.purge_quality.lower()
    items = call(spec["port"], spec["version"], key, FILE_ENDPOINTS[name]["items"]) or []

    victims = []
    for item in items:
        for entry in files_for(name, spec, key, item):
            recorded = quality_name(entry)
            if needle in recorded.lower():
                title = item.get("title") or item.get("artistName") or item["id"]
                victims.append((item, entry, title, recorded))

    total = sum(int(entry.get("size") or 0) for _i, entry, _t, _q in victims)
    label = f"{name}"
    if not victims:
        log(f"{label}: nothing recorded as {args.purge_quality!r}")
        return 0, 0

    log(f"{label}: {len(victims)} file(s) match {args.purge_quality!r}, {total / 1024 ** 3:.1f} GiB")
    for _item, _entry, title, recorded in victims[:10]:
        log(f"    {title[:60]:62} {recorded}")
    if len(victims) > 10:
        log(f"    ... and {len(victims) - 10} more")

    if not args.apply:
        return 0, total
    if args.limit:
        victims = victims[: args.limit]

    endpoint = FILE_ENDPOINTS[name]["delete"]
    deleted = 0
    freed = 0
    for _item, entry, title, recorded in victims:
        try:
            call(spec["port"], spec["version"], key, f"{endpoint}/{entry['id']}", method="DELETE")
        except ApiError as error:
            warn(f"{name}: could not delete {title}: {error}")
            continue
        deleted += 1
        freed += int(entry.get("size") or 0)
        log(f"    deleted {title[:50]} ({recorded})")
    log(f"{label}: deleted {deleted} file(s), {freed / 1024 ** 3:.1f} GiB freed")
    return deleted, freed


def purge_main(args):
    """Delete files by recorded quality, so the applications re-acquire them.

    This is the deliberate downgrade: removing the file takes away the baseline
    the application compares a release against, so the next search accepts
    anything that meets the profile instead of having to beat a remux.
    """
    apps = load_apps()
    names = [n for n in (parse_apps(args.app) if args.app else sorted(apps)) if n in FILE_ENDPOINTS]
    if not names:
        sys.exit("no application to purge (radarr, sonarr and lidarr are supported)")

    if not args.apply:
        log(f"DRY RUN - would delete files whose quality contains {args.purge_quality!r}")
    total_deleted = 0
    total_freed = 0
    for name in names:
        try:
            deleted, freed = purge_app(name, apps[name], args)
        except ApiError as error:
            warn(f"{name}: {error}")
            continue
        total_deleted += deleted
        total_freed += freed
        log("")

    if args.apply:
        log(f"purged {total_deleted} file(s), {total_freed / 1024 ** 3:.1f} GiB freed")
        log("now run `servarr-sweep --apply` to look for replacements")
    else:
        log(f"dry run: {total_freed / 1024 ** 3:.1f} GiB would be freed")
    return 0


# Reassigning existing items to a profile. Recyclarr creates and updates
# profiles but never assigns them - which profile a film or series uses is
# per-item data - so removing the Remux tier from the profiles does nothing for
# the items already on the old ones until they are moved.
ASSIGN_ENDPOINTS = {
    "radarr": {"items": "/movie", "editor": "/movie/editor", "ids": "movieIds"},
    "sonarr": {"items": "/series", "editor": "/series/editor", "ids": "seriesIds"},
}

# What AUTO migrates each application TO. Radarr has both resolution tiers;
# Sonarr has only the one, because the guides have no non-remux "Bluray + WEB"
# for TV - dropping Remux there means dropping Bluray too.
ASSIGN_TARGETS = {
    "radarr": {"uhd": "UHD Bluray + WEB", "hd": "HD Bluray + WEB"},
    "sonarr": {"hd": "WEB-1080p"},
}

AUTO_PROFILE = "AUTO"

# AUTO only touches items still on a profile whose name contains this. That is
# what the migration is FOR, and it keeps everything else where it is - which
# matters most in Sonarr, where the anime series belong on their own "Anime"
# profile and moving them to the WEB-only one would drop Bluray sourcing.
REMUX_MARKER = "remux"


def tallest_resolution(name, spec, key, item):
    """Whether this item holds a file at 2160p, and whether it holds any file.

    Derived from the FILES, not from the profile name. Basing it on the name is
    not idempotent: once an item is moved to "UHD Bluray + WEB" the name no
    longer contains "2160", so a second run would decide it was a 1080p item and
    move it down - silently downgrading every 4K film in the library.
    """
    if name == "radarr":
        media = (item.get("movieFile") or {}).get("mediaInfo") or {}
        resolution = media.get("resolution") or ""
        return resolution, bool(item.get("movieFile"))

    files = call(
        spec["port"], spec["version"], key, "/episodefile", params={"seriesId": item["id"]}
    ) or []
    resolutions = [(f.get("mediaInfo") or {}).get("resolution") or "" for f in files]
    return ("2160p" if any(r.startswith("2160") for r in resolutions) else ""), bool(files)


def assign_app(name, spec, args):
    """Move every item of one application onto the intended quality profile."""
    key = api_key(spec["dir"])
    if key is None:
        warn(f"{name}: no API key readable from {spec['dir']} (run this as root)")
        return 0

    endpoints = ASSIGN_ENDPOINTS[name]
    profiles = call(spec["port"], spec["version"], key, "/qualityprofile") or []
    id_for = {profile["name"]: profile["id"] for profile in profiles}
    name_for = {profile["id"]: profile["name"] for profile in profiles}

    def target_for(item):
        current = name_for.get(item.get("qualityProfileId"), "")
        if args.assign_profile != AUTO_PROFILE:
            return args.assign_profile
        if REMUX_MARKER not in current.lower():
            # Not on a Remux profile: this is not the migration's business.
            return None

        targets = ASSIGN_TARGETS[name]
        resolution, has_file = tallest_resolution(name, spec, key, item)
        if has_file:
            # Keep the resolution the item actually has: 4K stays 4K where a
            # 2160p target exists, and everything else goes to the HD target.
            if resolution.startswith("2160") and "uhd" in targets:
                return targets["uhd"]
            return targets["hd"]
        # No file to measure, so respect the tier the current profile declares
        # rather than silently dropping a film that is meant to be 4K.
        if "2160" in current or "4k" in current.lower():
            if "uhd" in targets:
                return targets["uhd"]
        return targets["hd"]

    groups = {}
    for item in call(spec["port"], spec["version"], key, endpoints["items"]) or []:
        current = name_for.get(item.get("qualityProfileId"), "")
        target = target_for(item)
        if target is None:
            continue
        if target not in id_for:
            warn(
                f"{name}: no quality profile named {target!r} here - this repository "
                f"only declares the profiles it manages (see recyclarr.nix). "
                f"Available in {name}: {', '.join(sorted(id_for))}"
            )
            return 0
        if current == target:
            continue
        groups.setdefault(target, []).append(item["id"])

    if not groups:
        log(f"{name}: every item is already on the intended profile")
        return 0

    for target, ids in sorted(groups.items()):
        log(f"{name}: {len(ids)} item(s) -> {target}")
    planned = sum(len(ids) for ids in groups.values())
    if not args.apply:
        return planned

    moved = 0
    for target, ids in sorted(groups.items()):
        body = {endpoints["ids"]: ids, "qualityProfileId": id_for[target]}
        try:
            call(spec["port"], spec["version"], key, endpoints["editor"], body=body, method="PUT")
        except ApiError as error:
            warn(f"{name}: could not assign {target}: {error}")
            continue
        moved += len(ids)
        log(f"{name}: assigned {len(ids)} item(s) to {target}")
    return moved


def assign_main(args):
    """Reassign Sonarr and Radarr items to the profiles Recyclarr now manages."""
    apps = load_apps()
    names = [
        name
        for name in (parse_apps(args.app) if args.app else sorted(apps))
        if name in ASSIGN_ENDPOINTS
    ]
    if not names:
        sys.exit("nothing to assign (radarr and sonarr are supported)")

    log("DRY RUN - nothing will be reassigned. Add --apply." if not args.apply else "assigning")
    log("")

    total = 0
    for name in names:
        try:
            total += assign_app(name, apps[name], args)
        except ApiError as error:
            warn(f"{name}: {error}")
        log("")

    if args.apply:
        log(f"reassigned {total} item(s)")
    else:
        log(f"dry run: {total} item(s) would be reassigned")
    return 0


def run_app(name, spec, args):
    key, commands = build_plan(name, spec, args)
    if key is None:
        return 0, 0

    if args.limit:
        commands = commands[: args.limit]

    total = len(commands)
    if not total:
        log(f"{name}: nothing with a file to search")
        return 0, 0

    log(f"{name}: {total} search command(s), about {human_duration(total * args.delay)} at {args.delay}s apart")
    if not args.apply:
        for label, _body in commands[:5]:
            log(f"    would search {label}")
        if total > 5:
            log(f"    ... and {total - 5} more")
        return 0, total

    sent = 0
    failed = 0
    started = time.monotonic()
    for index, (label, body) in enumerate(commands, 1):
        try:
            call(spec["port"], spec["version"], key, "/command", body=body)
            sent += 1
        except ApiError as error:
            failed += 1
            warn(f"{name}: {label}: {error}")
        if index % 10 == 0 or index == total:
            elapsed = time.monotonic() - started
            log(f"    {index}/{total} sent ({sent} ok, {failed} failed, {human_duration(elapsed)} elapsed)")
        if index < total:
            time.sleep(args.delay)

    log(f"{name}: done, {sent} search command(s) accepted, {failed} failed")
    return sent, failed


def parse_apps(raw):
    names = []
    for chunk in raw:
        names += [part.strip().lower() for part in chunk.split(",") if part.strip()]
    return names


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Ask each *arr application to search its indexers for better releases "
            "of what is already in the library. Prints the plan unless --apply is given."
        )
    )
    parser.add_argument("--app", action="append", default=None, metavar="NAME[,NAME]",
                        help="sonarr, radarr or lidarr (default: all of them)")
    parser.add_argument("--delay", type=float, default=10.0,
                        help="seconds between search commands (default: 10)")
    parser.add_argument("--limit", type=int, default=0,
                        help="stop after this many commands per application (default: no limit)")
    parser.add_argument("--sonarr-mode", choices=("season", "episode"), default="season",
                        help="search whole seasons (default, finds packs) or single episodes")
    parser.add_argument("--purge-quality", metavar="SUBSTRING",
                        help="instead of searching: delete every file whose recorded quality "
                             "contains this text (e.g. 'remux'). Deleting through the API makes "
                             "the application see the item as missing, so its next search accepts "
                             "anything meeting the profile rather than having to beat the file "
                             "that was there. Dry run unless --apply")
    parser.add_argument("--assign-profile", nargs="?", const=AUTO_PROFILE, default=None,
                        metavar="NAME",
                        help="reassign Sonarr/Radarr items off the Remux profiles, then exit. "
                             "With no NAME, only items currently on a profile containing "
                             "'remux' are moved - 2160p items to 'UHD Bluray + WEB', the rest to "
                             "'HD Bluray + WEB' (Radarr) or 'WEB-1080p' (Sonarr) - so anything "
                             "on another profile, such as Sonarr's Anime profile, is left "
                             "alone. Pass a NAME to force one profile on everything. Dry run "
                             "unless --apply")
    parser.add_argument("--apply", action="store_true",
                        help="actually send the searches; without it this is a dry run")
    args = parser.parse_args()

    if args.assign_profile is not None:
        return assign_main(args)

    if args.purge_quality:
        return purge_main(args)

    apps = load_apps()
    wanted = parse_apps(args.app) if args.app else sorted(apps)
    unknown = [n for n in wanted if n not in apps]
    if unknown:
        sys.exit(f"unknown application(s): {', '.join(unknown)} (known: {', '.join(sorted(apps))})")

    if not args.apply:
        log("DRY RUN - no searches will be sent. Add --apply to do it.")
    log(f"pace: one search command every {args.delay}s")
    log("")

    total_sent = 0
    total_failed = 0
    for name in wanted:
        try:
            sent, failed = run_app(name, apps[name], args)
        except ApiError as error:
            warn(f"{name}: {error}")
            continue
        total_sent += sent
        total_failed += failed
        log("")

    if args.apply:
        log(f"sweep finished: {total_sent} search command(s) accepted, {total_failed} failed")
    else:
        log("dry run finished; nothing was sent")
    return 1 if total_failed else 0


if __name__ == "__main__":
    sys.exit(main())
