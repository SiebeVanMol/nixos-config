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

## 1. Traps in the (currently disabled) Minecraft tree

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

## 2. Alex's git identity

`users/alexander/programs.nix:66-72` sets `git.settings.user` to Snowy Renard /
snowyrenard@gmail.com, so every commit made on that machine is authored as
Snowy. It dates from the initial copy of the user directory and survived the
`userName`/`userEmail` migration untouched. Deliberate sharing cannot be ruled
out from the repo, but nothing says so - and authorship is painful to correct
after it is pushed.

## 3. Smaller

- Scripts are nushell (`AGENTS.md`); ported so far: `alert-webhook`,
  `arr-api-key`, `homepage-env` (was 91 lines of bash with an embedded Python
  heredoc for Bazarr), `prune-generations`, and the daily health check
  (`system/maintenance/health-check.nu`, which was awk/grep/sed inside
  monitoring.nix). What is left, smallest first: the two udev hooks in
  `system/hardware/usb-automount.nix` (its session scan is already verified
  against a fake `/run/user`); the weekly report in
  `system/maintenance/reclaim.nix`; the bash one-liners in
  `lib/flake-packages.nix` (`rebuild` and the three python wrappers, where the
  shell only sets PATH/argv and `exec`s - the least value per conversion); and
  `test.sh`, last because it is the gate itself and a bug there breaks every
  verification.
  Behaviour is verified by running the result. `checks.x86_64-linux.nu` only
  parses, so a conversion needs either a real run (health check: "all clear"
  before and after, plus a stubbed-fixture run that forces all twelve findings)
  or a fixture (`prune-generations` deletes generations, so its counting and its
  `nix-env` invocation were tested against a stubbed command).
- Browser search engines and bookmarks are written out in full in both users'
  modules (`users/snowyrenard/browser.nix:96-291`,
  `users/alexander/browser.nix:26-181`) and have already drifted: one sends
  `channel=unstable` where the other sends `type=options` (a parameter
  `search.nixos.org/options` ignores), and `release=master` appears on only one.
  Worth one shared value of `{engines, bookmarks}`; keep the container/extension
  setup - and the two browsers - per user.
- `features/hyprland/home.nix:153` binds SUPER+SHIFT+E to `hyprshutdown`, which nothing
  installs, with `hyprctl dispatch 'hl.dsp.exit()'` as the fallback. Whether
  this Hyprland accepts the Lua-style dispatcher name is unverified - check it
  on the running compositor before changing, and add the package if the fade is
  what was wanted.
- `system/server/media/servarr-sweep.py:131` requests `/episode` once per series
  to learn which seasons have files, where `/series` already carries
  `seasons[].statistics.episodeFileCount` (39 series today). Verify the payload
  on the live instance once, then keep the per-series call only for the
  `episode` mode.

## 4. The *arr apps accept any Host header

`radarr reports warning: Allowed Hosts is not configured` - the daily health check
prints it on every run. The same `config/host` PUT that converged the web-UI login
carries this too (`allowedHosts` is one more field beside `authenticationMethod`),
so the fix is a dozen lines in `servarr-sync`. Measured, not inferred: the exposure
is bounded by the proxy, which only answers site addresses it knows, so this is
DNS-rebinding hardening rather than the key disclosure the login fix closed - which
is why it is written here instead of being folded into that work. Check whether the
other three applications report it before writing the convergence.

## Considered and deferred

Decided, not open — kept here with the condition that would reopen each one, so
the same options are not re-argued from scratch.

- **Cross-class `features/<name>/{system,home}.nix`.** Would co-locate the few
  things that straddle the two trees: the model server in `features/hermes/system.nix` that
  `features/hermes/home.nix` reads through `osConfig`, and `home/shell/*`
  against the shell `system/default.nix` sets. Rejected for now: a new directory
  convention plus an aggregation rule for two features, when a table in
  `AGENTS.md` answers the same question. Reopen if a third or fourth feature
  straddles, or if the two halves of one start drifting apart.
- **Dendritic (flake-parts + `import-tree`).** Would replace the host table and
  the module lists with named aspects, and hold a feature's system and user
  halves in one file. Rejected for now: a framework and a concept (aspect
  classes) to save two short import lists, and it makes "why is this applied
  here?" harder rather than easier. Reopen if the machine list grows past a
  handful, or if composing variants by name becomes the normal way work happens.
  Nothing currently blocks it: the modules are ordinary NixOS and Home Manager
  modules, `lib/` holds plain functions, and `homeConfigurations` is derived from
  the same host table any rewrite would use.
- **Subflakes / flake partitions.** Would give each component its own lock.
  Rejected: a NixOS module always evaluates against the host's package set, so a
  nested lock buys bookkeeping rather than independence, and per-subflake
  `nix flake update` is how the stale `nixpkgs` in `nix-minecraft` came about.
- **Generating options from the tree.** Removed in the toggle commit: modules
  declare their own `device.<area>.<file>.enable` and
  `checks.x86_64-linux.toggles` enforces the convention. Not coming back — the
  options were real but less findable than the metaprogram making them.

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
  nothing in `features/hermes/home.nix` needed editing because the whole
  local block (endpoint, aliases, cron default, aux slots) is gated on that flag.
  If it is re-enabled, the open question to measure is what still wakes it with
  no one asking - title generation at session start is the known one.

## Recently done (do not re-do)

- Overlays are applied where their package is used, not by the host. `flake.nix` no
  longer has a per-host `overlays = [...]` list: `system/server/media/{seerr,soularr,
  houndarr}.nix` add their overlay inside the `device.app.jellyfin` gate, and
  `users/snowyrenard/programs.nix` (amethyst) and `users/*/browser.nix` (nur's
  add-ons, via `nur.overlays.default pkgs pkgs`) import the file into a `let`. So
  enabling the media stack on another machine now brings its overlays with it
  instead of needing a matching edit in `flake.nix`, and a machine that never names
  a pin never evaluates it. Two dead groups went with it: `minecraft` (nothing
  applies the overlay; only the module is imported) and `nur` (consumed by the
  browsers now). Proof of neutrality: all three hosts' toplevel drvPaths are
  byte-identical before and after, and the four pins still evaluate as
  `.#packages.<system>` for `nix-update`.
  - Still worth doing: the weekly `overlay-pins` check queries all four pins from
    every machine that enables it, including the laptop, where the media three are
    unused. Deriving the list from `device.app.jellyfin.enable` (plus amethyst, which
    every host running the check installs) would make it match reality.
  - `nix flake lock` also taught a small lesson: `vpn-confinement` declares no
    inputs, so `inputs.nixpkgs.follows` on it produces "override for a non-existent
    input 'nixpkgs'" at every evaluation. Only inputs that actually pull nixpkgs
    need the line.
- Apps follow caelestia's scheme, and two silent failures that had been hiding it
  are fixed. What the investigation established:
  - Caelestia themes external apps itself, from a `theme` block in
    `~/.config/caelestia/cli.json`; every flag defaults to on, and `apply_colours`
    runs on every scheme and wallpaper change. GTK (gtk.css for GTK4, gtk-theme and
    `color-scheme` through dconf), Qt (needs `qtengine`, which nixpkgs does not
    ship), terminal palettes (OSC sequences written into every /dev/pts), btop,
    htop, nvtop, cava, fuzzel, Discord (needs `sass`), spicetify, pandora, zed,
    warp, chromium policies.
  - Three things were needed for the ones that exist here: `adw-gtk3`, because
    apply_gtk writes the `adw-gtk3-dark` name and GTK3 falls back to its default
    theme when that resolves to nothing; `color_theme = "caelestia"` in btop's
    settings, or the generated theme file is ignored; and the GTK3 light/dark
    variant, because caelestia writes `adw-gtk3-dark` in *both* modes, so light mode
    kept dark chrome - theme-apply.nu now picks the variant that matches `mode`.
  - `ExecStart` was a bare store path while `writeNuBin` produces a directory, so
    caelestia-theme-apply died with status 203/EXEC on every trigger: the path unit
    kept starting it, it kept dying in 2ms, and colours were never re-applied. It
    needs `lib.getExe`.
  - Zen browser follows the mode through `zen.view.window.scheme = 2` (0 dark,
    1 light, 2 auto). The profile had 0, pinned dark. On 2 it reads
    `prefers-color-scheme`, which on Wayland comes from the
    `org.freedesktop.appearance` portal - the value caelestia's dconf write already
    drives (verified through `busctl`: 1 in dark, 2 in light), so the browser flips
    with the control centre and web pages follow because Firefox's
    `layout.css.prefers-color-scheme.content-override` defaults to "system". The
    browser chrome takes the mode but not the exact palette: Gecko cannot be
    restyled at runtime, so matching caelestia's colours would mean a generated
    `userChrome.css` that only applies on the next start.
  - The path unit had also died with `unit-start-limit-hit`, because each rapid
    wallpaper change rewrites scheme.json and restarts the oneshot, and five
    failures in ten seconds is systemd's default limit. `StartLimitIntervalSec = 0`
    on the service fixes that; the unit is idempotent, so the limit bought nothing.
- Wallpapers are changed on command (`SUPER+ALT+W` from everything,
  `SUPER+ALT+1` from `Art`) and Hyprland no longer reloads when it happens.
  What the investigations established, since none of it is guessable:
  - `caelestia wallpaper -r [DIR]` takes an optional directory and recurses
    (`rglob`) under it, so "pick from this subfolder" needs no upstream change;
    only the launcher's picker is flat (shell PR #2135, "folder navigation", open).
    Upstream has no time-based schedule in a release: PR #1203 (a `wallpaperSchedule`
    of `{startTime, wallpaper}`) has been a draft since March, #1819 is an
    interval-only rival, and the closed request #1308 was answered with "use a
    systemd timer" - which is what the login-time rotation already is.
  - A wallpaper change rewrites the colour scheme, and the theme step used to
    finish with `hyprctl reload`. That reload is what broke the cursor in games:
    it re-applies the cursor theme and drops pointer state for every surface.
  - Hyprland 0.56 parses Lua, so `hyprctl keyword` refuses outright ("keyword
    can't work with non-legacy parsers. Use eval."); the live path is
    `hyprctl eval 'hl.config({...})'`, which returns `ok` and touches nothing else.
    Lua tables take braces, not brackets - `{colors = {"rgb(..)"}}`, and a failed
    eval exits 7 with the reason on stdout, so the script uses `complete`.
  - `misc.disable_autoreload = true` stops the reload-on-file-change too, since
    caelestia rewrites `scheme/current.lua` whenever the wallpaper changes. The
    cost is explicit: config edits now land on `hyprctl reload`, including after a
    rebuild.
  - `open` on a `.json` file already parses it; handing the result to `from json`
    is "only string input data is supported", hence `open --raw`.
- The overlay pins are current, all four, and `nix run .#update-overlays -- --check`
  exits 0: seerrng 3.19.3 -> 3.67.0, soularr unstable-2026-07-31 -> 1.2.2,
  amethyst 2.5.3 -> 2.5.5, houndarr unchanged. Three things had to be true first,
  each worth knowing next time:
  - seerrng's new release wants `engines.node ^24.15.0`, and nixpkgs' `seerr`
    recipe takes node and pnpm as *callPackage arguments* named after the versions
    it pins (`nodejs-slim_22`, `pnpm_10`). A `let` binding in the overlay changes
    only what the file computes - the build still ran node 22 and failed on the
    same engine check. The bump goes through `.override`.
  - GitHub's source tarball for 3.67.0 contains no `docs/` at all, while the
    package's `prebuild` runs `current-batch:check`, which reads
    `docs/maintainers/current-batch-acceptance-ledger.md`. A tarball checkout
    cannot build the release; `fetchgit` can. (The repo also moved to
    `snapetech-org`.)
  - soularr needed `finalAttrs` rather than `_:` to use `tag = "v${version}"`,
    since the source was pinned to a bare commit while upstream had no tags.
  All three build: `nix build .#seerrng|soularr|amethyst-mod-manager`.
  Runtime is untested - a 48-release jump of a Next.js app with a SQLite database
  is the kind of thing that migrates on first start, so back up
  `/var/lib/seerr` before switching and watch `journalctl -u seerr`.
- `nix run .#tasks` is the menu: it lists every command the flake exports (discovered
  from `packages.<system>` and their `meta.description`) plus the checkout tasks
  (test, fmt, switch, hm-switch, flake-update, gc), marks the ones that need root,
  and runs the pick with the arguments passed through (`-- update-overlays
  --check`). Four helpers gained `meta.description` so they no longer appear
  blank. The overlay packages and `tasks` itself are excluded with the reason in
  the script: they are exported for nix-update, not to be run.
- The daily health check is nushell (`system/maintenance/health-check.nu`, read by
  monitoring.nix with the tool paths, mounts and two binaries substituted in).
  Verified two ways: on this host it prints "nixos health check: all clear" and
  exits 0, as the bash version did; and against stubbed `systemctl`/`df`/`btrfs`/
  `lsblk`/`smartctl`/`arr-health`/`alert-webhook`, its output is byte-identical to
  the bash version's for the same fixtures (twelve findings, same order, same
  webhook header, exit 1). Two nushell traps recorded in its comments: `(s)`
  inside a `$"..."` string is read as a subexpression, and a `def` that takes a
  parameter cannot receive piped input - it needs `$in`.
- The overlay pins are now addressable and watched: `packages.x86_64-linux` exports
  the four overlay packages so `nix-update` has an attribute to rewrite and
  `nix build .#seerrng` works; `overlays/update.nu` (run as
  `nix run .#update-overlays [-- --check]`) compares each pin against upstream via
  the GitHub API, updates the mechanical ones with a build as the proof and a
  revert on failure, and names why the other two are hand work;
  `system/maintenance/overlays.nix` runs `--check` weekly on the hosts that hold
  the checkout and posts what it finds to the alert webhook.
- `checks.x86_64-linux.nu` runs `nu --ide-check` over every `*.nu` and fails on
  error diagnostics, which closes the gap where a nu script was parsed by
  nothing (verified with a deliberately broken fixture: the check named the file
  and the diagnostic).
- Overlays apply per host instead of to all three (`flake.nix`'s
  `overlayGroups` table and each host row's `overlays` list): nur everywhere
  for the browser add-ons, amethyst where snowyrenard's NXM handlers live, the
  media three only on nixos-desktop, and the minecraft overlay kept for the
  disabled tree. `pkgs.seerrng` and `pkgs.amethyst-mod-manager` now resolve on
  exactly the hosts that use them, and all three toplevel drvPaths are
  unchanged - the spike had already measured that dropping them from
  alex-desktop moves nothing.
- Qwen3.8-27B is out of the model set (`features/hermes/system.nix`): four
  models now, and the `qwen27` alias is gone with it. It measured 38.7 t/s decode
  and 37 t/s prefill at 512 tokens on this card, 14.8 GB resident, no draft head
  (the published MTP head took it to 15.8, so it was never pinned) - the prefill
  was a third of what owners report for the same quant, which is what an agent's
  20-40k prompt pays, and the ROCm experiment was never run to explain it. Its
  weights are now unreferenced and the next GC reclaims them; the entry can come
  back from the pin in this repository's history if the prefill question matters
  again.

- The flake lints the shell files in the tree (`checks.x86_64-linux.shell`,
  shellcheck over every `*.sh`): `test.sh` and `homepage-env.sh` were only
  `bash -n` clean. Shell inside Nix strings is not covered, but that shell is
  built by `writeShellApplication`, which shellchecks it in its own checkPhase.
- `device.app.gamemode.enable` owns the gamemode daemon again: `steam.nix` no
  longer sets `programs.gamemode.enable` beside it, which had made the toggle
  unable to turn gamemode off on any host. All three toplevel derivations are
  unchanged, and forcing the toggle false on nixos-desktop now reports false.
- The USB udev hooks share one session scan
  (`usb-automount-sessions.sh`), so a bus socket whose uid is not in passwd is
  skipped by the notification too, not just by the mount. Exercised against a
  fake `/run/user`.

- The Discord post has one implementation (`lib/alert-webhook.nix`), read from
  stdin with its header as the argument: `monitoring.nix`'s health check and
  `reclaim.nix`'s weekly report both pipe into it, so the 1800-character
  truncation against Discord's cap, the `jq -n --arg content` envelope and the
  `curl -sfS` POST exist once. Neither unit carries `jq` or `curl` on its own
  PATH any more. Exercised against a local HTTP endpoint: 4230 characters of
  report arrived as `header + 1800`, the exit status stayed 0 on an unreachable
  webhook, and an unset `ALERT_WEBHOOK_URL` is still journal-only.
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
  written three times in `features/hermes/home.nix`.
- SeerrNG service keys are asserted once per boot for every app, not once per
  link (`system/server/media/servarr-sync.py`).
- Host feature toggles are declared by the module that owns them: a file in
  `system/{app,hardware,security,wm}/` carries its own
  `options.device.<area>.<file>.enable = lib.mkEnableOption "..."` beside the
  `mkIf` that reads it, and `checks.x86_64-linux.toggles` fails if one is
  missing or if an unconditional module is not named in that check. This
  replaced `system/options.nix`, which generated the options from file names
  and scraped their descriptions from the first comment line: the options were
  real but less findable than the metaprogram making them. Verified
  behaviour-preserving - same 25 option names and defaults, and the toplevel
  derivation path of all three hosts is unchanged.
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
