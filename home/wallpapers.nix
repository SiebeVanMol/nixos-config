# Aggregate the user's wallpapers into ~/Pictures/Wallpapers by symlinking
# ~/Pictures/Backgrounds into it, for anything that looks there. Caelestia does
# NOT: it is pointed straight at ~/Pictures/Backgrounds in ./caelestia.nix
# because its FileSystemModel does not follow symlinks. The existence check
# happens at activation time (pure flake evaluation forbids reading ~ at eval
# time), so users without that folder are unaffected.
{lib, ...}: {
  home.activation.createWallpaperLinks = lib.hm.dag.entryAfter ["writeBoundary"] ''
    WAL="$HOME/Pictures/Wallpapers"
    mkdir -p "$WAL"
    if [ -d "$HOME/Pictures/Backgrounds" ]; then
      ln -sfn "$HOME/Pictures/Backgrounds" "$WAL/Backgrounds"
    fi
  '';
}
