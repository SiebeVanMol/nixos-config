# Steam with Remote Play, LAN transfer, gamemode integration, and Proton GE.
{
  config,
  lib,
  pkgs,
  ...
}: let
  internalNetworks = import ../../lib/internal-networks.nix {inherit lib;};
in {
  config = lib.mkIf config.device.app.steam.enable {
    programs.steam = {
      enable = true;
      protontricks.enable = true;

      # Both flags would open their ports on every interface - including the one
      # the router forwards from the internet. Left off and reopened for the LAN
      # and the Tailscale mesh by the rules below, so the feature works without
      # becoming an internet-facing service.
      remotePlay.openFirewall = false;
      localNetworkGameTransfers.openFirewall = false;

      # Make gamemode available to every Steam title. Games can use it either
      # via the `gamemoderun %command%` launch option or through the daemon
      # enabled below (which is what makes it available by default).
      extraPackages = with pkgs; [gamemode vulkan-loader];
      extraCompatPackages = with pkgs; [proton-ge-bin];
    };

    # The ports those two flags would have opened, copied from the Steam module's
    # own list but reachable from the local network only:
    #   remotePlay                 TCP 27036-27037, UDP 10400-10401, UDP 27031-27035
    #   localNetworkGameTransfers  TCP 27040, and UDP 27036 peer discovery
    # This host has a single interface, so "local" is expressed by source address.
    networking.firewall.extraCommands = internalNetworks.localOnly {
      tcp = ["27036" "27037" "27040"];
      udp = ["10400" "10401" "27031:27035" "27036"];
    };

    # Run generic dynamically-linked Linux binaries (e.g. GE-Proton/Wine launched
    # outside Steam's FHS sandbox). NixOS's stub-ld blocks these because /lib and
    # /usr/lib do not exist; nix-ld supplies the loaders and libraries so Proton
    # can exec wine, and vulkan-loader makes libvulkan.so.1 visible to its probe.
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        glibc
        stdenv.cc.cc.lib # libstdc++ / libgcc_s
        zlib
        libGL # libGL / libGLX / libEGL
        libxcb
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
