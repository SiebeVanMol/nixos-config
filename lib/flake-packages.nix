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
      } (builtins.readFile ../system/server/jellyfin/servarr-sync.py)}/bin/servarr-sync-export --export "$@"
    '';
  };
}
