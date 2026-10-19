# Symlink ~/Pictures/Backgrounds into ~/Pictures/Wallpapers for anything that
# looks there. Caelestia does NOT: it points straight at Backgrounds
# (./caelestia.nix) because its FileSystemModel does not follow symlinks. The
# existence check runs at activation time, so users without the folder are fine.
{lib, ...}: {
  home.activation.createWallpaperLinks = lib.hm.dag.entryAfter ["writeBoundary"] ''
    WAL="$HOME/Pictures/Wallpapers"
    mkdir -p "$WAL"
    if [ -d "$HOME/Pictures/Backgrounds" ]; then
      ln -sfn "$HOME/Pictures/Backgrounds" "$WAL/Backgrounds"
    fi
  '';
}
