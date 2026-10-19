# The overlay pin updater, built from overlays/update.nu.
#
# Two consumers: `packages.update-overlays` (a person running it from the flake)
# and the weekly timer in system/maintenance/overlays.nix, which only ever passes
# `--check`. Both need the same PATH substitution, and a second copy of it in the
# module would be a second place for the placeholders to drift apart.
#
# The script is nushell but shells out to nix, nix-update and git, and a nushell
# script cannot declare its own dependencies: `PATH_FROM_NIX` is replaced here
# with their store paths, and the script's first statement prepends it.
{pkgs}:
pkgs.writers.writeNuBin "update-overlays" (
  builtins.replaceStrings
  ["PATH_FROM_NIX"]
  ["${pkgs.lib.makeBinPath [pkgs.nix pkgs.nix-update pkgs.git]}"]
  (builtins.readFile ../overlays/update.nu)
)
