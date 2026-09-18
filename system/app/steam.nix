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

      # Remote Play and LAN game transfers are local-network features, but both
      # flags open their ports on every interface - including the one the router
      # forwards from the internet. Leave them off and reopen exactly the same
      # ports for the LAN and the Tailscale mesh in the rules below, so the
      # feature keeps working without becoming an internet-facing service.
      remotePlay.openFirewall = false;
      localNetworkGameTransfers.openFirewall = false;

      # Make gamemode available to every Steam title. Games can use it either
      # via the `gamemoderun %command%` launch option or through the daemon
      # enabled below (which is what makes it available by default).
      extraPackages = with pkgs; [gamemode vulkan-loader];
      extraCompatPackages = with pkgs; [proton-ge-bin];
    };

    # The same ports the two openFirewall flags above would have opened, copied
    # from the Steam module's own list, but reachable from the local network
    # instead of from everywhere:
    #   remotePlay                 TCP 27036-27037, UDP 10400-10401, UDP 27031-27035
    #   localNetworkGameTransfers  TCP 27040, and UDP 27036 peer discovery
    # This host sits behind a single network interface, so "from the local
    # network" has to be expressed by source address rather than by interface.
    networking.firewall.extraCommands = internalNetworks.localOnly {
      tcp = ["27036" "27037" "27040"];
      udp = ["10400" "10401" "27031:27035" "27036"];
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
