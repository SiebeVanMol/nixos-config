# overlays/amethyst-mod-manager.nix
#
# Amethyst Mod Manager (https://github.com/ChrisDKN/Amethyst-Mod-Manager), a
# Linux-native game mod manager, not in nixpkgs.
#
# Upstream only ships an AppImage, and appimageTools.extract cannot unpack it (a
# sharun layout the e_shoff heuristic misses), so it is unpacked with the
# AppImage's own --appimage-extract. It is launched through `steam-run`, whose
# FHS runtime supplies the 32-bit FreeType, glibc, Vulkan loader and X11 client
# libraries Wine needs; a custom buildFHSEnv was tried first but did not reliably
# expose libfreetype.so.6 to Wine, making the VC++ installer exit 130.
#
# The nxm:// / ror2mm:// desktop entries live in users/snowyrenard/home.nix.
_final: prev: let
  version = "2.5.5";
  src = prev.fetchurl {
    url = "https://github.com/ChrisDKN/Amethyst-Mod-Manager/releases/download/v${version}/AmethystModManager-${version}-x86_64.AppImage";
    hash = "sha256-9U7p9g+8WcD+BQV1Llfn08Mgeg2/dSVaaixVRI63Z9Q=";
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
