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

## 1. Narrow the overlay surface

`flake.nix:99` applies five third-party overlays to every host, but
`alex-desktop` never enables jellyfin (`hosts/AlexDesktop/default.nix:25-28`,
`system/options.nix:50-52`) and uses none of the media packages. Gating them
means re-evaluating all three hosts afterwards: any shared module naming
`pkgs.seerrng` would fail on a host that skips the overlay. The comment at
`flake.nix:31-34` already argues the per-user pattern for agent software, which
is also how hermes is imported.

## 2. One report-delivery path

`monitoring.nix:143-145` and `reclaim.nix:146-147` each hand-roll the same
Discord post: the same `${report:0:1800}` truncation against Discord's
2000-character cap, `jq -n --arg content`, and the same `curl -sfS -X POST`
against the same `EnvironmentFile` (`monitoring.nix:192`, `reclaim.nix:215`). A
fix to the cap or the failure handling in one leaves the other wrong. Extract
one helper (a `lib/` function emitting the shell fragment, or a
`writeShellApplication` reading the report on stdin).

## 3. Traps in the (currently disabled) Minecraft tree

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

## 4. Alex's git identity

`users/alexander/programs.nix:66-72` sets `git.settings.user` to Snowy Renard /
snowyrenard@gmail.com, so every commit made on that machine is authored as
Snowy. It dates from the initial copy of the user directory and survived the
`userName`/`userEmail` migration untouched. Deliberate sharing cannot be ruled
out from the repo, but nothing says so - and authorship is painful to correct
after it is pushed.

## 5. Smaller

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
- Nothing lints the shell the modules carry (`homepage-env.sh` and friends):
  the flake checks Nix formatting and Python, but no `shellcheck`. They do pass
  `bash -n`, so this is a gap, not a breakage.
- `system/app/steam.nix:72` sets `programs.gamemode.enable`, so
  `device.app.gamemode.enable` (`system/app/gamemode.nix:7-8`) cannot turn
  gamemode off on any host - all three set both. Pick one owner.
- `home/hyprland.nix:153` binds SUPER+SHIFT+E to `hyprshutdown`, which nothing
  installs, with `hyprctl dispatch 'hl.dsp.exit()'` as the fallback. Whether
  this Hyprland accepts the Lua-style dispatcher name is unverified - check it
  on the running compositor before changing, and add the package if the fade is
  what was wanted.
- `system/server/media/servarr-sweep.py:131` requests `/episode` once per series
  to learn which seasons have files, where `/series` already carries
  `seasons[].statistics.episodeFileCount` (39 series today). Verify the payload
  on the live instance once, then keep the per-series call only for the
  `episode` mode.

## 6. The *arr apps accept any Host header

`radarr reports warning: Allowed Hosts is not configured` - the daily health check
prints it on every run. The same `config/host` PUT that converged the web-UI login
carries this too (`allowedHosts` is one more field beside `authenticationMethod`),
so the fix is a dozen lines in `servarr-sync`. Measured, not inferred: the exposure
is bounded by the proxy, which only answers site addresses it knows, so this is
DNS-rebinding hardening rather than the key disclosure the login fix closed - which
is why it is written here instead of being folded into that work. Check whether the
other three applications report it before writing the convergence.

## 7. Qwen3.8-27B prefills at 37 t/s

Measured on this card with the service's own flags: 38.7 t/s decode over 512
tokens and 37 t/s prefill, 14.8 GB resident (it fits, no spill), and that is
with no draft head - the MTP head the repository publishes takes it to 15.8 t/s,
so it is not fetched. Decode is close to what owners report; prefill is a third
of it, and prefill is what an agent's 20-40k prompt actually pays. The likely cause
is the 3-bit IQ3 path on Vulkan rather than the model, so the cheap experiment is
`device.app.ai.backend = "rocm"` - one line, and the HIP build is already written
for gfx1201. Keep or drop the model on that result.

## Notes

- Measuring local speed: 512 tokens, the service's own flags, and the card
  waited down between cases (`mem_info_vram_used` back under ~2.6 GiB before the
  next load). Not doing that produced a 3x spread on identical flags - 18.2 and
  55.7 t/s for the same model - because `--fit` plans against the VRAM free at
  that instant, so a model still resident from the previous case makes the next
  one spill. Two stale servers left over from earlier runs were the other half of
  it. Short runs are just as misleading the other way: a 32-token completion read
  64.6 t/s on a model that does 75.4 over 512.

- `test.sh` is the repo's single entry point: everything `nix flake check`
  runs (formatter and Python lint - it builds them rather than only evaluating
  them, which is what it used to do),
  then evaluation of every host with its hostname assertion. It reads the host
  list from `nixosConfigurations`, so a new host is covered without an edit. The
  eval step forces each host's toplevel derivation, which is what walks unit text
  and service configuration: a shallow attribute check passed while a wrong key
  under `serviceConfig` reached a real rebuild, and `nix flake check` does not
  catch that either. Forcing the toplevel is how it was found.
- A `buildEnv` collision is invisible to every check here. `nix flake check`
  and the per-host eval both passed while a switch failed twice on
  `home-manager-path` (two packages providing `bin/cargo`, then `bin/rust-analyzer`
  - rustup ships shims for both). The check that catches it is building the
  profile itself: `nix build <host>.config.home-manager.users.<user>.home.path`,
  which is cheap once its inputs are in the store.
- Removing a home module does not remove what it left behind: `~/.dsh` still
  holds the dropped DeepSeek harness's state, and its `dsh-web.service` keeps
  running until the switch that deletes the unit. State under `$HOME` is the
  user's to delete.
- `nix flake check` prints a firefox XDG-path deprecation warning. It comes from
  the third-party zen-browser module's use of home-manager's legacy
  `configPath`, not from anything in this repo.
- The llama-server on `nixos-desktop` is **deliberately off**
  (`hosts/nixos-desktop/default.nix`, `ai.enable = false`): a model holds its
  weights on the card for the fifteen-minute idle window after any request, and
  the owner wanted that VRAM back. It is a switch away from coming back, and
  nothing in `users/snowyrenard/hermes.nix` needed editing because the whole
  local block (endpoint, aliases, cron default, aux slots) is gated on that flag.
  If it is re-enabled, the open question to measure is what still wakes it with
  no one asking - title generation at session start is the known one.

## Recently done (do not re-do)

- `seerrng` is `prev.seerr.overrideAttrs`, not a copy of nixpkgs' derivation
  (`overlays/seerrng.nix`). Upstream's pnpm build now arrives with every
  nixpkgs bump; only `postInstall` (the wrapper is named `seerr` upstream) and
  `pnpmDeps` (a fork's own lockfile) are restated. The re-derivation differs
  from the old copy only in whitespace inside `installPhase`, and both trees
  were compared - 60163 files each.
- Weights are store paths now, not runtime downloads. Every model entry carries
  `sha256` (Hugging Face's LFS object id is the file's sha256, so a pin is filled
  in without downloading anything), `--models-dir` and the draft directory are
  `linkFarm`s over those fixed-output files, and `llama-fetch` is gone with the
  tmpfiles rules that used to create `/Vault/llama/*`. 55 GB now sits in `/nix`,
  which is its own 1.9 TB mount with 688 GB free - not the 32 GB root. The price
  is that a revision bump leaves the old copy until the next GC and that a model
  can no longer be deleted by hand. The migration cost no bandwidth: the files
  already on /Vault were seeded with `nix store add-file`, which produces exactly
  the path `fetchurl` names for the same bytes (verified on one file before
  trusting it for 54 GB).

- The local server serves five models and four of them decode with a draft head.
  `agent` (35B-A3B) carries its head fused in the MTP repository's own quants;
  `quick` (gemma 4 12B) takes `MTP/mtp-gemma-4-12B-it-Q8_0.gguf`, the new `oss`
  (gpt-oss-20b MXFP4) an EAGLE3 head, and the new `qwen27` (Qwen3.8-27B at
  IQ3_S) its MTP head. Heads are fetched into `/Vault/llama/drafts` - outside
  `--models-dir`, because the router would otherwise advertise a 0.5-1.4 GB head
  as a model - and wired per model through a `--models-preset` INI, since one
  global `--spec-type` cannot say "this model has a head and that one does not".
  Measured through the router at the 64K window the service uses, 32-token
  completion over 512 tokens on a card waited down between cases (the only
  numbers worth quoting - see the Notes entry on measurement): `agent` 75.4 t/s
  with the head against 33-40 without, `gpt-oss-20b` 222.8 against 161.5, `quick`
  155.8 against 64.5, `tiny` 178.4 with no head on purpose, and `qwen27` 38.7 -
  which is *without* its head, because the published one takes it down to 15.8.
  Three things only running it could have found: the preset loader rejects
  `spec-draft-cache-type-k` ("not recognized in preset", which fails the whole
  router rather than one model) even though `--spec-draft-type-k` exists on the
  command line, so the draft cache stays at its f16 default; `hf` writes 0600
  under the invoking user's umask and a DynamicUser service cannot read that, so
  `llama-fetch` now chmods what it wrote; and `/Vault/llama` is root-owned, so
  the drafts directory is created by tmpfiles and the first head fetch has to
  follow a switch.
- The idle window is five minutes, not fifteen (`sleep-idle-seconds`), and the
  desktop's `ai.enable` is back on. Fifteen minutes was why it was switched off:
  one request held a model on the card for a quarter of an hour. Five minutes is
  the same trade with the hold cut by two thirds, and a sleeping model still
  comes back on the next request with no client change.

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
- Host feature toggles are derived from the tree: a module in
  `system/{app,hardware,security,wm}/` gets `device.<area>.<file>.enable` from
  its own file name and its own description from its first comment line, so
  adding a feature no longer edits `system/options.nix`. A module earns a toggle
  by reading one, which is what keeps the unconditional modules in those
  directories unconditional. The four features whose paths are not their option
  names (jellyfin, music, ai, minecraft) declare their enable in their own
  modules, as does `device.security.reverse-proxy.publicDomain`.
  Verified behaviour-preserving: the full option surface is identical, and the
  toplevel derivation path of all three hosts is unchanged by the migration.
- The media scripts share one *arr client (`system/server/media/arr_client.py`),
  which `lib/arr-client.nix` puts on PYTHONPATH in all seven places that build
  one of them. Six `api_key()` copies, six HTTP clients and three version probes
  became one implementation behind a small per-script adapter, so each script
  kept its own call convention - method before path, a sweep's query parameters
  and 120 s timeout, `arr-health` never raising, `torrent-cleanup`'s probe -
  while the plumbing lives once: 233 lines net out of the six scripts, against a
  163-line module. `servarr-sync`'s Seerr helper was the last copy holding its
  own request; converting it also ended the drift where an unparseable body
  raised in one path and returned `None` in another. `torrent-cleanup` keeps
  `http_json`, which polls the download client's queue and is not an *arr API.
  Verified against the live stack rather than by import alone: 401 with the
  status set, `probe_version` telling "unauthorized" from "down", a real Seerr
  403 body parsed into the message, and every tool rebuilt and re-run after.
  Confirmed in production once the rebuild landed: all four wrappers in the
  running system carry the same store `arr_client.py`, and the two units that
  re-ran on that switch exited 0 doing real work - `servarr-sync` converged all
  three Seerr links (the helper converted last), `houndarr-config` read every
  app's key out of its root-only config.xml through the shared reader.
- The *arr application facts live in `lib/arr-apps.nix`: port, dashboard row,
  and how to address each application's library. The three that own one are
  built by `media.mkArr` from it (a module now names only its own
  `writePaths`), Prowlarr's port and state directory come from it, and it is the
  single source for the JSON the media scripts read - read from a host's *live*
  registry where there is one, since ports are options.
  That deleted three Python copies (`arr-health`, `media-recode`,
  `servarr-sweep`), the literal `sonarr radarr lidarr prowlarr` loop in
  `homepage-env.sh` - which would have given a fifth application no widget key,
  silently - and every stored API version: those are probed now, because the
  literal went stale the last time Sonarr changed major version.
  Verified: before the Python half, the system derivation of all three hosts was
  byte-identical to the previous commit; afterwards each loader was exercised
  against a fake *arr server (`arr-health` took port and state directory from the
  module's JSON and its key from config.xml, on the expected path, then reported
  the finding) or against the live stack (`servarr-sweep` reporting
  `unauthorized` for a wrong key and `down` for a dead port).
- `deepseek-harness` (dsh) is gone: the flake input, its overlay, the
  `overlays/dsh-model-router.nix` bundle, the home module that was applied to
  every user, and Snowy's `dsh` / `services.dsh` configuration. `nix flake lock`
  dropped the input and its three sub-inputs from the lock, and all three hosts
  still evaluate without it.
- Every media web UI requires a login. `initialize.json` handed the
  application's API key to anything it counted as local, and behind the proxy
  that is every LAN and Tailscale request: `servarr-sync` now converges
  `authenticationMethod = forms` with `authenticationRequired = enabled` (only
  while that is not already right, and reading the value back afterwards), with
  the password generated at activation into
  `~/.local/share/servarr/ui-password` under `lib/arr-apps.nix:uiAuth` - never in
  the store, and owned by the user at 0400 so that reading it needs no root
  shell while the root-run consumers read it all the same. Bazarr gets it through its own
  module's `_secret` mechanism, which hands the unit the password as a systemd
  credential, because its API has nowhere to put it. The API keys the scripts use
  are untouched: `X-Api-Key` bypasses the UI login by design.
  Verified against a fake *arr server, since the real one needs root: the put
  carries the three fields with the password read from the file, a second run is
  a no-op, a method set by hand (`basic`) is left alone, an API that ignores the
  change is reported by the read-back rather than assumed, and a missing password
  file leaves the UI open and says so. Measured live since (all four apps accept
  the file's password through the proxy and refuse a lowercased or space-padded
  one), which is the half a fake server cannot cover; what remains unchecked is a
  browser, since nothing in this shell can drive one.
- Seerr's copy of each application's root folder is converged. Seerr sends its
  own `activeDirectory` with every request as `rootFolderPath`, and no field
  owned it, so the library move from `/Vault/Jellyfin` to `/Vault/Media` reached
  Sonarr's root folder and every series but not the requester: every series
  request died on `RootFolderExistsValidator: Root folder
  '/Vault/Jellyfin/Shows' does not exist` and was marked FAILED, while
  `servarr-sync` reported `seerr: sonarr link already correct` (measured in the
  journal: four such requests, two on Oct 6 and two on Oct 18). Movie requests
  would have failed the same way; none had been tried. `seerr_directory_fixes`
  replaces a field only when it names a root folder the application does not
  have - a valid one is a choice, not drift - taking the declared root folder
  from `root_folders` or the application's only one, and warning instead of
  guessing when there are several. Verified against fake Seerr and Sonarr
  servers: stale converge, second run a no-op, a deliberate `Anime` folder left
  alone, ambiguity warned, single root folder used with no declaration.
  Not yet observed live: the links still hold the stale path until the next
  switch or the 05:00 timer run, which needs root.
- Soularr's two API keys no longer travel as command-line arguments (a root
  process's environment is readable only by root, its argv by every local user),
  and its `config.ini` is owned by the service account at 0400 instead of being
  readable by the whole `users` group.
- `checks.x86_64-linux.python` lints every `.py` file with the same flake8
  command `pkgs.writers.writePython3Bin` runs during a build. That was the only
  linting any of this got, and it never covered the shared module (delivered by
  `writeTextDir`, which no writer lints) or the scripts no module builds.
