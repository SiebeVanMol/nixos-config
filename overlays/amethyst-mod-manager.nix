# Overlay providing Amethyst Mod Manager (https://github.com/ChrisDKN/Amethyst-Mod-Manager).
# A Linux native mod manager for a variety of games.
#
# Upstream only ships an AppImage. nixpkgs' appimageTools.extract can't unpack
# it (it uses a sharun layout the e_shoff offset heuristic misses), so we unpack
# via the AppImage's own --appimage-extract instead.
#
# The app is wrapped in a buildFHSEnv so it and everything it spawns (Pandora's
# Proton, BodySlide, Outfit Studio) find the standard library/data paths that a
# bare NixOS host lacks:
#   - /usr/lib/libvulkan.so.1 from vulkan-loader: Pandora's Proton does
#     CDLL('libvulkan.so.1') in vulkan.py, and Amethyst strips LD_LIBRARY_PATH
#     before spawning Proton (Utils/appimage_env.py drops LD_LIBRARY_PATH), so
#     the loader must be reachable via the default /usr/lib path instead.
#   - /usr/share/X11/xkb from xkeyboard-config: the bundled BodySlide/Outfit
#     Studio tools ship their own libs but read XKB rules from that path.
#   - xdg-open (xdg-utils): the free-account Nexus "slow download" flow opens
#     the mod's page in the default browser with it.
# Desktop entries for the nxm:// / ror2mm:// protocol handlers are defined in
# users/snowyrenard/home.nix and route through this same wrapper.
final: prev: let
  version = "2.3.0";
  src = prev.fetchurl {
    url = "https://github.com/ChrisDKN/Amethyst-Mod-Manager/releases/download/v${version}/AmethystModManager-${version}-x86_64.AppImage";
    hash = "sha256-8ztyvLXEonHY0RTTt+shOVCkvVg7J1u1qm1eB1VL+1Y=";
  };

  unpacked = prev.runCommand "amethyst-mod-manager-${version}-unpacked" {} ''
    cp ${src} amethyst.AppImage
    chmod +x amethyst.AppImage
    ./amethyst.AppImage --appimage-extract
    mkdir -p $out
    # squashfs-root is a symlink to ./AppDir; follow it.
    cp -rL "$(readlink -f squashfs-root)/." "$out/"
  '';

  fhs = prev.buildFHSEnv {
    name = "amethyst-mod-manager";
    targetPkgs = pkgs:
      with pkgs; [
        xdg-utils # xdg-open for the Nexus download flow
        xkeyboard-config # XKB rules for BodySlide/Outfit Studio
        vulkan-loader # libvulkan.so.1 for Proton's vulkan.py probe
        glib
        glibc
        gcc.cc.lib # libstdc++ / libgcc_s
        zlib
        libGL
        # X11 client libs: GE-Proton's wine x11drv display driver needs these to
        # connect to the X display (XWayland) and create windows; without libX11
        # wine fails with "no driver could be loaded".
        libX11
        libXext
        libXrandr
        libXi
        libXinerama
        libXcursor
        libXrender
        libXxf86vm
        libxkbcommon
        libxcb
        fontconfig
        freetype
      ];
    multiPkgs = pkgs:
      with pkgs; [
        glibc
        gcc.cc.lib
        zlib
        # 32-bit glibc + gcc: GE-Proton's files/bin/wine is a 32-bit launcher that
        # requests /lib/ld-linux.so.2, which the FHS must provide or wine cannot
        # exec ("/lib/ld-linux.so.2: could not open").
        pkgsi686Linux.glibc
        pkgsi686Linux.gcc.cc.lib
      ];
    runScript = prev.writeShellScript "amethyst-mod-manager-run" ''
      export APPDIR="${unpacked}"
      cd "$APPDIR"
      exec "$APPDIR/AppRun" "$@"
    '';
  };
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
      ln -s ${fhs}/bin/amethyst-mod-manager $out/bin/amethyst-mod-manager
      cp ${unpacked}/mod-manager.desktop $out/share/applications/amethyst-mod-manager.desktop
      cp ${unpacked}/mod-manager.png $out/share/icons/hicolor/512x512/apps/amethyst-mod-manager.png
      sed -i \
        's#^Exec=.*#Exec=amethyst-mod-manager %u#; s#^Icon=.*#Icon=amethyst-mod-manager#' \
        $out/share/applications/amethyst-mod-manager.desktop
    '';
}
