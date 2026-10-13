# Jellyfin itself: the media server the video/book stack feeds.
{
  config,
  lib,
  pkgs,
  media,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # AMD OpenCL for tone mapping
    hardware.graphics.extraPackages = lib.mkIf config.device.hardware.mesa.enable [
      pkgs.libva
      pkgs.libva-vdpau-driver
      pkgs.libvdpau-va-gl
      pkgs.rocmPackages.clr.icd
    ];

    # Reachable only through the Caddy reverse proxy (80/443), so no direct
    # firewall port. `group = "users"` because every service writes into the same
    # tree; the module default made Jellyfin's metadata readable only by itself.
    services.jellyfin = {
      enable = true;
      group = "users";
    };

    # The whole media tree, because Jellyfin presents all of it (films, shows,
    # books, manga, music) and writes metadata and images beside the files.
    systemd.services.jellyfin.serviceConfig = media.vaultRw [media.mediaRoot];

    environment.systemPackages = with pkgs; [
      # Server
      jellyfin
      jellyfin-web
      jellyfin-ffmpeg
    ];

    device.media.services.jellyfin = {
      port = 8096;
      public = true;
      dashboard = {
        group = "library";
        order = 10;
        title = "Jellyfin";
        description = "Watch";
        icon = "jellyfin.png";
      };
      backup = {
        sqliteRoots = ["/var/lib/jellyfin"];
        statePaths = ["/var/lib/jellyfin/config"];
      };
    };
  };
}
