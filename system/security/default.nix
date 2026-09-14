{lib, ...}: let
  importDir = import ../../lib/import-dir.nix {inherit lib;};
in {
  imports = importDir ./.;
}
