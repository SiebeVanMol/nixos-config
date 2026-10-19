# The flake's own helper commands, kept out of flake.nix so that file stays a
# readable entry point: inputs, hosts, and where each piece lives.
{pkgs}: let
  # The shared *arr client every media script imports; on PYTHONPATH via the
  # wrapper each writer builds (lib/arr-client.nix explains the mechanism).
  arrClient = import ./arr-client.nix {inherit pkgs;};

  # ...and the shared application facts, as the JSON the scripts read. This is
  # the one consumer that cannot take them from a host's configuration: these
  # commands run outside any host. Passed with --set-default, so pointing a run
  # at a different file still wins.
  arrAppsJSON = pkgs.writeText "arr-apps.json" (import ./arr-apps.nix {lib = pkgs.lib;}).scriptsJSON;
in {
  # Run the formatter and then nixos-rebuild, with --flake filled in and sudo
  # added for the subcommands that need it.
  rebuild = pkgs.writeShellScriptBin "rebuild" ''
    set -euo pipefail

    # Find the flake root (directory containing flake.nix).
    ROOT="$(pwd)"
    while [[ "$ROOT" != "/" && ! -f "$ROOT/flake.nix" ]]; do
      ROOT="$(dirname "$ROOT")"
    done
    if [[ ! -f "$ROOT/flake.nix" ]]; then
      echo "error: could not find flake.nix from $(pwd)" >&2
      exit 1
    fi

    cd "$ROOT"
    ${pkgs.nix}/bin/nix fmt .

    # Only add --flake if the user didn't already pass one.
    if [[ "$*" != *"--flake"* ]]; then
      set -- --flake "$ROOT" "$@"
    fi

    needs_sudo=false
    for arg in "$@"; do
      case "$arg" in
        switch|boot|test|rollback|build-vm-with-bootloader)
          needs_sudo=true
          ;;
      esac
    done

    if $needs_sudo; then
      exec sudo nixos-rebuild "$@"
    else
      exec nixos-rebuild "$@"
    fi
  '';

  # Read-only dump of the two services whose configuration lives only in their own
  # databases (Prowlarr's indexers and SeerrNG's service links). Both APIs are
  # root-only: `sudo nix run .#servarr-export`. Prints a paste-ready Nix snippet
  # with every private field marked; never writes to either service.
  # Update the pins in overlays/: `nix run .#update-overlays -- --check` reports
  # only, which is what the weekly timer runs; without it the pins that are
  # behind are updated by nix-update and built. The script and its PATH
  # substitution live in lib/overlay-updater.nix, because the timer builds the
  # same thing and two copies of the substitution would drift.
  update-overlays = import ./overlay-updater.nix {inherit pkgs;};

  servarr-export = pkgs.writeShellApplication {
    name = "servarr-export";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec ${pkgs.writers.writePython3Bin "servarr-sync-export" {
        flakeIgnore = ["E501"];
        makeWrapperArgs = ["--set" "PYTHONPATH" "${arrClient}"];
      } (builtins.readFile ../system/server/media/servarr-sync.py)}/bin/servarr-sync-export --export "$@"
    '';
  };

  # One-off "go and find better rips" sweep: ask each *arr application to search
  # its indexers for better releases of the whole library. Houndarr does the same
  # but caps at five an hour, so this is the front-loading counterpart.
  #   sudo nix run .#servarr-sweep                      # dry run
  #   sudo nix run .#servarr-sweep -- --apply           # one search every 10s
  # Root because the API keys live in 0700 config files. The pacing matters: each
  # search reaches every indexer and the public trackers rate-limit bursts.
  servarr-sweep = pkgs.writeShellApplication {
    name = "servarr-sweep";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec ${pkgs.writers.writePython3Bin "servarr-sweep" {
        flakeIgnore = ["E501"];
        makeWrapperArgs = [
          "--set"
          "PYTHONPATH"
          "${arrClient}"
          "--set-default"
          "ARR_APPS"
          "${arrAppsJSON}"
        ];
      } (builtins.readFile ../system/server/media/servarr-sweep.py)}/bin/servarr-sweep "$@"
    '';
  };

  # Temporary space measure: re-encode the library's over-encoded tail (remuxes),
  # measured by bits-per-pixel rather than a hand-written list, and refresh each
  # application's record so its native-upgrade hunt keeps working.
  #   sudo nix run .#media-recode              # dry run
  #   sudo nix run .#media-recode -- --apply   # needs ffmpeg with the encoder
  # Dry run by default; refuses an output that is not meaningfully smaller or
  # whose duration moved - see the module docstring.
  media-recode = pkgs.writeShellApplication {
    name = "media-recode";
    runtimeInputs = [pkgs.python3 pkgs.ffmpeg];
    text = ''
      # ffmpeg dlopen()s AMD's AMF runtime rather than linking it, so
      # --encoder av1_amf (and hevc_amf) need it on the loader path or they fail
      # with "cannot load AMF runtime", leaving only the weaker VAAPI option.
      export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [pkgs.amf]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec ${pkgs.writers.writePython3Bin "media-recode" {
        flakeIgnore = ["E501"];
        makeWrapperArgs = [
          "--set"
          "PYTHONPATH"
          "${arrClient}"
          "--set-default"
          "ARR_APPS"
          "${arrAppsJSON}"
        ];
      } (builtins.readFile ../system/server/media/media-recode.py)}/bin/media-recode "$@"
    '';
  };
}
