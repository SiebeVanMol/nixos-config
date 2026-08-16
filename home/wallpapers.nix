# Aggregate the user's wallpapers into ~/Pictures/Wallpapers (caelestia's default
# wallpaper directory). If ~/Pictures/Backgrounds exists, it is symlinked there so
# caelestia's picker can find the wallpapers. The existence check happens at
# activation time (pure flake evaluation forbids reading ~ at eval time), so
# users without that folder are unaffected.
{ lib, ... }: {
  home.activation.createWallpaperLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    WAL="$HOME/Pictures/Wallpapers"
    mkdir -p "$WAL"
    if [ -d "$HOME/Pictures/Backgrounds" ]; then
      ln -sfn "$HOME/Pictures/Backgrounds" "$WAL/Backgrounds"
    fi
  '';
}
