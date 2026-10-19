# The flake's own helper commands, kept out of flake.nix so that file stays a
# readable entry point: inputs, hosts, and where each piece lives.
#
# Every command here is nushell (the repository's rule): each one is a `*.nu` file
# beside this one, read and wrapped by `pkgs.writers.writeNuBin`, so `checks.nu`
# parses it and no shell string hides inside a Nix file. The Python the three media
# commands drive stays Python - the nushell part is the wrapper that gives it its
# PYTHONPATH and defaults.
{pkgs}: let
  # The shared *arr client every media script imports; on PYTHONPATH via the
  # wrapper each writer builds (lib/arr-client.nix explains the mechanism).
  arrClient = import ./arr-client.nix {inherit pkgs;};

  # ...and the shared application facts, as the JSON the scripts read. This is
  # the one consumer that cannot take them from a host's configuration: these
  # commands run outside any host. Passed with --set-default, so pointing a run
  # at a different file still wins.
  arrAppsJSON = pkgs.writeText "arr-apps.json" (import ./arr-apps.nix {lib = pkgs.lib;}).scriptsJSON;

  # The Python each command wraps. Built here rather than in the wrapper text so a
  # `.nu` file holds no store path and stays ordinary nushell.
  exportPython = pkgs.writers.writePython3Bin "servarr-sync-export" {
    flakeIgnore = ["E501"];
    makeWrapperArgs = ["--set" "PYTHONPATH" "${arrClient}"];
  } (builtins.readFile ../system/server/media/servarr-sync.py);

  sweepPython = pkgs.writers.writePython3Bin "servarr-sweep" {
    flakeIgnore = ["E501"];
    makeWrapperArgs = [
      "--set"
      "PYTHONPATH"
      "${arrClient}"
      "--set-default"
      "ARR_APPS"
      "${arrAppsJSON}"
    ];
  } (builtins.readFile ../system/server/media/servarr-sweep.py);

  recodePython = pkgs.writers.writePython3Bin "media-recode" {
    flakeIgnore = ["E501"];
    makeWrapperArgs = [
      "--set"
      "PYTHONPATH"
      "${arrClient}"
      "--set-default"
      "ARR_APPS"
      "${arrAppsJSON}"
    ];
  } (builtins.readFile ../system/server/media/media-recode.py);

  # `writeNuBin` takes no `meta`, and `nix run .#tasks` reads `meta.description`
  # for every task it lists, so the description is attached here.
  describe = description: drv:
    drv.overrideAttrs (old: {
      meta =
        (old.meta or {})
        // {
          inherit description;
        };
    });
in {
  # Format the tree, then nixos-rebuild, filling in --flake and adding sudo only
  # for the subcommands that need it. `nix` comes from the wrapper's PATH;
  # `nixos-rebuild` and `sudo` deliberately come from the caller's, so the command
  # rebuilds the running system rather than a pinned copy of it.
  rebuild = describe "format the tree, then nixos-rebuild with --flake filled in (sudo for switch/test/boot)" (
    pkgs.writers.writeNuBin "rebuild" {
      makeWrapperArgs = ["--prefix" "PATH" ":" (pkgs.lib.makeBinPath [pkgs.nix])];
    } (builtins.readFile ./rebuild.nu)
  );

  # Read-only dump of the two services whose configuration lives only in their own
  # databases (Prowlarr's indexers and SeerrNG's service links). Both APIs are
  # root-only: `sudo nix run .#servarr-export`. Prints a paste-ready Nix snippet
  # with every private field marked; never writes to either service.
  # What this repository can do: `nix run .#tasks` lists every command the flake
  # exports plus the tasks that act on the checkout, and runs the one you pick.
  # The list is discovered from `packages.<system>` and each entry's `meta`, so a
  # new helper appears here without an edit to a second list.
  tasks = pkgs.writers.writeNuBin "tasks" {
    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (pkgs.lib.makeBinPath [pkgs.nix pkgs.git pkgs.coreutils])
    ];
  } (builtins.readFile ./tasks.nu);

  # Update the pins in overlays/: `nix run .#update-overlays -- --check` reports
  # only, which is what the weekly timer runs; without it the pins that are
  # behind are updated by nix-update and built. The script and its PATH
  # substitution live in lib/overlay-updater.nix, because the timer builds the
  # same thing and two copies of the substitution would drift.
  update-overlays = describe "compare the overlay pins against upstream and update the ones that can be (`-- --check` to only report)" (
    import ./overlay-updater.nix {inherit pkgs;}
  );

  servarr-export = describe "dump Prowlarr indexers and Seerr service links as a Nix snippet (sudo, read-only)" (
    pkgs.writers.writeNuBin "servarr-export" {
      makeWrapperArgs = ["--prefix" "PATH" ":" (pkgs.lib.makeBinPath [exportPython])];
    } (builtins.readFile ./servarr-export.nu)
  );

  # One-off "go and find better rips" sweep: ask each *arr application to search
  # its indexers for better releases of the whole library. Houndarr does the same
  # but caps at five an hour, so this is the front-loading counterpart.
  #   sudo nix run .#servarr-sweep                      # dry run
  #   sudo nix run .#servarr-sweep -- --apply           # one search every 10s
  # Root because the API keys live in 0700 config files. The pacing matters: each
  # search reaches every indexer and the public trackers rate-limit bursts.
  servarr-sweep = describe "ask every *arr app to search for better releases of the whole library (sudo; --apply to act)" (
    pkgs.writers.writeNuBin "servarr-sweep" {
      makeWrapperArgs = ["--prefix" "PATH" ":" (pkgs.lib.makeBinPath [sweepPython])];
    } (builtins.readFile ./servarr-sweep.nu)
  );

  # Temporary space measure: re-encode the library's over-encoded tail (remuxes),
  # measured by bits-per-pixel rather than a hand-written list, and refresh each
  # application's record so its native-upgrade hunt keeps working.
  #   sudo nix run .#media-recode              # dry run
  #   sudo nix run .#media-recode -- --apply   # needs ffmpeg with the encoder
  # Dry run by default; refuses an output that is not meaningfully smaller or
  # whose duration moved - see the module docstring.
  media-recode = describe "re-encode the library's over-encoded tail, measured by bits-per-pixel (sudo; --apply to act)" (
    pkgs.writers.writeNuBin "media-recode" {
      # ffmpeg dlopen()s AMD's AMF runtime rather than linking it, so --encoder
      # av1_amf (and hevc_amf) fail with "cannot load AMF runtime" without it on
      # the loader path, leaving only the weaker VAAPI option.
      makeWrapperArgs = [
        "--prefix"
        "PATH"
        ":"
        (pkgs.lib.makeBinPath [recodePython pkgs.ffmpeg])
        "--prefix"
        "LD_LIBRARY_PATH"
        ":"
        (pkgs.lib.makeLibraryPath [pkgs.amf])
      ];
    } (builtins.readFile ./media-recode.nu)
  );
}
