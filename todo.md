# TODO

Open work on this configuration, most valuable first.

Provenance: a read-only whole-tree cleanup pass (2026-10-16) by five reviewers,
one per area, with the four angles (reuse, quality, efficiency, altitude). What
that pass could verify it fixed (see "Recently done"): it ran `test.sh` end to
end - format check, `nix flake check`, and evaluation of all three hosts - and
syntax-checked the Python it touched. It could not rebuild or switch anything
(`sudo` is blocked for the agent shell), so the entries below are
**read-verified, not measured**: re-check the named lines before acting, and
treat every "after the change" claim as something to test.

## 1. Consolidate the media Python clients

Six scripts carry the same things:

- `api_key()`, byte-equivalent in `servarr-sync.py:69`, `arr-health.py:38`,
  `torrent-cleanup.py:65`, `houndarr-config.py:110`, `servarr-sweep.py:77`,
  `media-recode.py:112` - while `lib/arr-api-key.nix` has existed all along for
  the shell side (used by `recyclarr.nix:20`, `soularr.nix:16`,
  `homepage.nix:15`). `arr-health.py:14-17` justifies the duplication with "a
  shared module would have to be built and referenced by both", which the
  existing helper already contradicts, and six copies of the why must now stay
  in step.
- An `*arr` HTTP client, once per script: `servarr-sync.py:120`,
  `servarr-sweep.py:97`, `media-recode.py:126`, `arr-health.py:57`,
  `torrent-cleanup.py:85`, plus `servarr-sync.py:939` for Seerr.
- A v3/v1 version probe three times: `servarr-sync.py:159`,
  `torrent-cleanup.py:100`, `arr-health.py:75`.

Deliberate differences that must become parameters, not be flattened: the
timeout (30 / 120 / 10 / 15 s), `arr-health` never raising (it always exits 0),
`media-recode`'s 120 s for long `/command` posts, and `torrent-cleanup` making
the key optional. `servarr-sync.py:144` raising on an unparseable body while
`:961` returns None silently is drift, not intent.

Test: run each script against the live stack after the change (`nix run` on its
package, or the unit) rather than only importing it.

## 2. Derive the *arr tables instead of hardcoding them

`arr-health.py:30-35`, `media-recode.py:81-97` and `servarr-sweep.py:48-52`
spell out port / dir / version (and items, path_key, rescan) that
`lib/media.nix:87-101` (`mkArr`) already derives; `servarr-sync.nix:22-25` and
`torrent-cleanup.nix:22-25` already receive that table as JSON. The hardcoded
copies are the ones that go stale when a service moves.

Related: `homepage-env.sh:35` loops over a literal `sonarr radarr lidarr
prowlarr` while the widget keys it must satisfy are generated from the registry
(`lib/media.nix:95` sets `keyVar`, `dashboard.nix:45` renders it), and
`homepage.nix:17` builds the script with no arguments - a fourth *arr app breaks
a dashboard widget with nothing saying why.

Caveat: the registry would have to grow `media-recode`'s per-app fields, or the
JSON generator keeps them once.

## 3. Fork nixpkgs' seerr instead of copying it

`overlays/seerrng.nix:14-88` is line-for-line nixpkgs' `seerr` derivation
(pnpmDeps, preBuild, prune, installPhase, makeWrapper) with only pname, version,
src, hash and the wrapper bin differing, so upstream recipe fixes never arrive.
`prev.seerr.overrideAttrs` would carry them; the cost is re-stating the
`postInstall` wrapper and inheriting upstream's bump cadence.
`system/server/media/seerr.nix:28` needs no change.

## 4. Narrow the overlay and module surface

`flake.nix:102-111` applies all six third-party overlays to every host, but
`alex-desktop` never enables jellyfin (`hosts/AlexDesktop/default.nix:25-28`,
`system/options.nix:50-52`) and uses none of the media or agent packages.
`flake.nix:105` + `:129` likewise impose the deepseek-harness overlay and home
module on every user, though only `users/snowyrenard` uses dsh
(`programs.nix:172-214`); the comment at `flake.nix:32-33` already argues for
the per-user pattern hermes uses. Re-evaluate all three hosts after gating:
any shared module naming `pkgs.seerrng` / `pkgs.dsh-model-router` would fail on a
host that skips the overlay.

## 5. One report-delivery path

`monitoring.nix:137-150` and `reclaim.nix:136-143` each hand-roll the same
Discord post: the same `${report:0:1800}` truncation against Discord's
2000-character cap, `jq -n --arg content`, and the same `curl -sfS -X POST`
against the same `EnvironmentFile` (`monitoring.nix:189`, `reclaim.nix:208`). A
fix to the cap or the failure handling in one leaves the other wrong. Extract
one helper (a `lib/` function emitting the shell fragment, or a
`writeShellApplication` reading the report on stdin).

## 6. Traps in the (currently disabled) Minecraft tree

No host enables it, so these matter on the day it is re-enabled:

- The UID hazard is recorded only in commit `35efb26`: world data under
  `/Vault/minecraft` keeps its numeric owner while re-enabling allocates a fresh
  uid for `users.users.minecraft` (`system/server/minecraft/default.nix:109`).
  Pin the uid, or move the warning into the file.
- The hardening is keyed to the literal unit name
  `systemd.services.minecraft-server-violet-town` (`default.nix:114-119`).
  Renaming or adding a server leaves the sandbox on a unit that no longer
  exists, with no evaluation error. Derive it from
  `config.services.minecraft-servers.servers`.
- `cobbleverse-mods.nix:1` cannot be re-derived or refreshed: 125 entries, 24 of
  which are absent from the pinned pack (it ships them as "do not enable"
  placeholders), no generator in the tree, and the pack-bump note at
  `default.nix:14-16` covers only the URL and hash.

## 7. Alex's git identity

`users/alexander/programs.nix:66-72` sets `git.settings.user` to Snowy Renard /
snowyrenard@gmail.com, so every commit made on that machine is authored as
Snowy. It dates from the initial copy of the user directory and survived the
`userName`/`userEmail` migration untouched. Deliberate sharing cannot be ruled
out from the repo, but nothing says so - and authorship is painful to correct
after it is pushed.

## 8. Smaller

- Browser search engines and bookmarks are written out in full in both users'
  modules (`users/snowyrenard/browser.nix:96-291`,
  `users/alexander/browser.nix:26-181`) and have already drifted: one sends
  `channel=unstable` where the other sends `type=options` (a parameter
  `search.nixos.org/options` ignores), and `release=master` appears on only one.
  Worth one shared value of `{engines, bookmarks}`; keep the container/extension
  setup - and the two browsers - per user.
- `system/hardware/usb-automount.nix:38-48` and `:73-80` each scan
  `/run/user/*/bus` to find logged-in sessions, with only one copy handling the
  `getent` failure.
- `system/app/steam.nix:72` sets `programs.gamemode.enable`, so
  `device.app.gamemode.enable` (`system/app/gamemode.nix:7-8`) cannot turn
  gamemode off on any host - all three set both. Pick one owner.
- `home/hyprland.nix:153` binds SUPER+SHIFT+E to `hyprshutdown`, which nothing
  installs, with `hyprctl dispatch 'hl.dsp.exit()'` as the fallback. Whether
  this Hyprland accepts the Lua-style dispatcher name is unverified - check it
  on the running compositor before changing, and add the package if the fade is
  what was wanted.
- `system/server/media/servarr-sweep.py:154` requests `/episode` once per series
  to learn which seasons have files, where `/series` already carries
  `seasons[].statistics.episodeFileCount` (39 series today). Verify the payload
  on the live instance once, then keep the per-series call only for the
  `episode` mode.

## Notes

- `test.sh` is the repo's single entry point: format check, `nix flake check`,
  then evaluation of every host with its hostname assertion. It reads the host
  list from `nixosConfigurations`, so a new host is covered without an edit.
- `nix flake check` prints a firefox XDG-path deprecation warning. It comes from
  the third-party zen-browser module's use of home-manager's legacy
  `configPath`, not from anything in this repo.

## Recently done (do not re-do)

- `hardware.uinput.enable` no longer duplicated by hand in `system/hardware/kernel.nix`.
- `system/wm/wayland.nix` no longer re-imports `fonts.nix` past the `importDir` glob.
- `pkgs.slskd-api` no longer exported with no consumer (`overlays/soularr.nix`).
- Stray `.chmod_test` ignore entry dropped; accidental exec bits cleared.
- Boot loader, NetworkManager and `stateVersion` hoisted to `system/default.nix`.
- `test.sh` reads the host list from the flake and compares hostnames
  case-insensitively (it previously could not evaluate `alex-desktop`).
- The formatting check's hand-written source filter dropped (cleanSourceFilter
  already drops `result`).
- fcitx5/Mozc, fastfetch and mangohud shared in `home/input-method.nix` and
  `home/desktop-apps.nix`; `btop` deliberately left per-user.
- `reclaim.nix` takes its `/Vault` paths from `lib/media.nix`, and its weekly
  "unfinished fragments" figure now counts all three incomplete trees it sweeps.
- The llama-server endpoint is derived from `device.app.ai.port` instead of being
  written three times in `users/snowyrenard/hermes.nix`.
- SeerrNG service keys are asserted once per boot for every app, not once per
  link (`system/server/media/servarr-sync.py`).
