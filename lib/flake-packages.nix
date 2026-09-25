# The flake's own helper commands, kept out of flake.nix so that file stays a
# readable entry point: inputs, hosts, and where each piece lives.
{pkgs}: {
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

  # Read-only dump of the two services whose configuration still lives only in
  # their own databases (Prowlarr's indexers and SeerrNG's service links). Both
  # APIs are root-only, hence:
  #
  #   sudo nix run .#servarr-export
  #
  # It prints a paste-ready Nix snippet with every private field marked, so those
  # settings can be declared in this repository instead of being re-clicked
  # after a rebuild. It never writes to either service.
  servarr-export = pkgs.writeShellApplication {
    name = "servarr-export";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec ${pkgs.writers.writePython3Bin "servarr-sync-export" {
        flakeIgnore = ["E501"];
      } (builtins.readFile ../system/server/media/servarr-sync.py)}/bin/servarr-sync-export --export "$@"
    '';
  };

  # One-off "go and find better rips" sweep: ask each *arr application to search
  # its indexers for better releases of everything already in the library.
  # Houndarr does the same searches but the engine caps it at five an hour per
  # instance, so this is the front-loading counterpart to that slow sweep.
  #
  #   sudo nix run .#servarr-sweep                      # dry run, prints the plan
  #   sudo nix run .#servarr-sweep -- --apply           # one search every 10s
  #
  # Root, like servarr-export, because the API keys live in 0700 config files.
  # The pacing is not decoration: each search reaches every indexer, and the
  # public trackers rate-limit a client that fires thousands of them at once.
  servarr-sweep = pkgs.writeShellApplication {
    name = "servarr-sweep";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec ${pkgs.writers.writePython3Bin "servarr-sweep" {
        flakeIgnore = ["E501"];
      } (builtins.readFile ../system/server/media/servarr-sweep.py)}/bin/servarr-sweep "$@"
    '';
  };

  # Temporary space measure: re-encode only the library's over-encoded tail
  # (remuxes), measured by bits-per-pixel rather than by a hand-written list, and
  # refresh each application's record so its native-upgrade hunt keeps working.
  #
  #   sudo nix run .#media-recode              # dry run, prints the plan
  #   sudo nix run .#media-recode -- --apply   # requires ffmpeg with the encoder
  #
  # Dry run by default, and it refuses to keep an output that is not
  # meaningfully smaller or whose duration moved - see the module docstring.
  media-recode = pkgs.writeShellApplication {
    name = "media-recode";
    runtimeInputs = [pkgs.python3 pkgs.ffmpeg];
    text = ''
      # ffmpeg dlopen()s AMD's AMF runtime rather than linking it, so --encoder
      # av1_amf (and hevc_amf) only work when it is on the loader path. Without
      # this line they fail with "cannot load AMF runtime" and the only AV1
      # option left is the weaker VAAPI one.
      export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [pkgs.amf]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec ${pkgs.writers.writePython3Bin "media-recode" {
        flakeIgnore = ["E501"];
      } (builtins.readFile ../system/server/media/media-recode.py)}/bin/media-recode "$@"
    '';
  };
}
