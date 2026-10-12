# overlays/amethyst-mod-manager.nix
#
# Overlay providing Amethyst Mod Manager (https://github.com/ChrisDKN/Amethyst-Mod-Manager),
# a Linux-native mod manager for a variety of games.
#
# Upstream only ships an AppImage. nixpkgs' appimageTools.extract can't unpack
# it (it uses a sharun layout the e_shoff offset heuristic misses), so we unpack
# via the AppImage's own --appimage-extract instead.
#
# The app is launched through `steam-run`, which drops it into Steam's FHS
# runtime. That runtime supplies the 32-bit FreeType, glibc, Vulkan loader,
# and X11 client libraries that Wine's 32-bit processes need. A custom
# buildFHSEnv was tried first but its multiPkgs/multiArch wiring does not
# reliably expose libfreetype.so.6 to Wine on this nixpkgs revision, causing
# the VC++ redistributable installer to exit with code 130.
#
# Desktop entries for the nxm:// / ror2mm:// protocol handlers are defined in
# users/snowyrenard/home.nix and route through this same wrapper.
_final: prev: let
  version = "2.5.3";
  src = prev.fetchurl {
    url = "https://github.com/ChrisDKN/Amethyst-Mod-Manager/releases/download/v${version}/AmethystModManager-${version}-x86_64.AppImage";
    hash = "sha256-trg9t3qzln7RTOjDyYA7UzpBlc+eZ+skpPlLgaQNPsg=";
  };

  unpacked = prev.runCommand "amethyst-mod-manager-${version}-unpacked" {} ''
    cp ${src} amethyst.AppImage
    chmod +x amethyst.AppImage
    ./amethyst.AppImage --appimage-extract
    mkdir -p $out
    # squashfs-root is a symlink to ./AppDir; follow it.
    cp -rL "$(readlink -f squashfs-root)/." "$out/"
  '';

  # Launch inside Steam's runtime so everything Amethyst spawns -- its own
  # Python, GE-Proton, BodySlide, Outfit Studio -- sees the 32-bit and 64-bit
  # libraries it expects at standard /usr/lib paths.
  wrapper = prev.writeShellScriptBin "amethyst-mod-manager" ''
    set -euo pipefail

    steam_run="${prev.steam-run}/bin/steam-run"
    if [ ! -x "$steam_run" ]; then
      echo "amethyst-mod-manager: steam-run not found at $steam_run" >&2
      exit 1
    fi

    export APPDIR="${unpacked}"
    cd "$APPDIR"
    exec "$steam_run" "$APPDIR/AppRun" "$@"
  '';
in {
  amethyst-mod-manager =
    prev.runCommand "amethyst-mod-manager-${version}" {
      meta = {
        description = "A Linux native mod manager for a variety of games";
        homepage = "https://github.com/ChrisDKN/Amethyst-Mod-Manager";
        license = prev.lib.licenses.gpl3Only;
        sourceProvenance = with prev.lib.sourceTypes; [binaryNativeCode];
        platforms = prev.lib.platforms.linux;
      };
    } ''
      mkdir -p $out/bin $out/share/applications $out/share/icons/hicolor/512x512/apps
      ln -s ${wrapper}/bin/amethyst-mod-manager $out/bin/amethyst-mod-manager
      cp ${unpacked}/mod-manager.desktop $out/share/applications/amethyst-mod-manager.desktop
      cp ${unpacked}/mod-manager.png $out/share/icons/hicolor/512x512/apps/amethyst-mod-manager.png
      sed -i \
        's#^Exec=.*#Exec=amethyst-mod-manager %u#; s#^Icon=.*#Icon=amethyst-mod-manager#' \
        $out/share/applications/amethyst-mod-manager.desktop
    '';
}
