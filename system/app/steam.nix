# Steam with Remote Play, LAN transfer, gamemode integration, and Proton GE.
{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.device.app.steam.enable {
    programs.steam = {
      enable = true;

      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;

      # Make gamemode available to every Steam title. Games can use it either
      # via the `gamemoderun %command%` launch option or through the daemon
      # enabled below (which is what makes it available by default).
      extraPackages = with pkgs; [gamemode vulkan-loader];
      extraCompatPackages = with pkgs; [proton-ge-bin];
    };

    # Run generic dynamically-linked Linux binaries (notably GE-Proton/Wine
    # launched directly by e.g. the Pandora Behaviour Engine Wizard, outside
    # Steam's FHS sandbox). NixOS's stub-ld blocks these by default because
    # /lib and /usr/lib don't exist; nix-ld provides the dynamic loaders and
    # libraries so Proton can exec wine. vulkan-loader also makes libvulkan.so.1
    # visible to Proton's vulkan probe (GE-Proton11-3's vulkan.py does
    # CDLL('libvulkan.so.1')).
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        glibc
        stdenv.cc.cc.lib # libstdc++ / libgcc_s
        zlib
        libGL # libGL / libGLX / libEGL
        xorg.libxcb
        libxkbcommon
        libX11
        libXext
        libXrandr
        libXi
        libXinerama
        libXcursor
        libXrender
        libXxf86vm
        fontconfig
        freetype
        libSM
        libICE
        openssl
        libusb1
        vulkan-loader
      ];
    };

    # Enable the Feral Gamemode daemon whenever Steam is enabled so games can
    # use gamemode out of the box.
    programs.gamemode.enable = true;
  };
}
