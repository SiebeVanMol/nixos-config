# Jellyfin itself: the media server every other part of this stack feeds.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stack = import ./layout.nix {inherit config lib;};
in {
  config = lib.mkIf stack.enabled {
    # AMD OpenCL for tone mapping
    hardware.graphics.extraPackages = lib.mkIf config.device.hardware.mesa.enable [
      pkgs.libva
      pkgs.libva-vdpau-driver
      pkgs.libvdpau-va-gl
      pkgs.rocmPackages.clr.icd
    ];

    # Jellyfin is reachable only through the Caddy reverse proxy (ports 80/443),
    # so no direct firewall port is opened here.
    services.jellyfin.enable = true;

    # Its own library, and nothing else on /Vault.
    systemd.services.jellyfin.serviceConfig = stack.vaultRw ["/Vault/Jellyfin"];

    environment.systemPackages = with pkgs; [
      # Server
      jellyfin
      jellyfin-web
      jellyfin-ffmpeg
    ];
  };
}
