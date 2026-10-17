# Jellyfin itself: the media server the video/book stack feeds.
{
  config,
  lib,
  pkgs,
  media,
  ...
}: {
  # Declared here rather than derived from the tree: this file is
  # server/media/jellyfin.nix, whose path is not its option name.
  options.device.app.jellyfin.enable = lib.mkEnableOption "Jellyfin media server";

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

    # Jellyfin's own network.xml is set through the API rather than here; the
    # module has no option for it. It carries KnownProxies = 127.0.0.1 and ::1,
    # without which every request arriving through Caddy is attributed to
    # loopback: a session shows 127.0.0.1 for a client on the other side of the
    # world, and because nobody looks remote, a per-user remote bitrate limit
    # has nothing to apply to. config/network.xml is inside the restic backup
    # below, which is what makes a runtime-only setting tolerable here.
    #
    # Deliberately NOT setting services.jellyfin.forceEncodingConfig. The
    # module's generated encoding.xml covers only about 19 of the ~45 elements
    # the server writes, so enabling it would replace the working file and
    # silently drop TranscodingTempPath, the tone-mapping algorithm/mode/range,
    # EncoderPreset, the deinterlace method and the segment/seek timings.
    # Transcoding is tuned through the dashboard instead, and encoding.xml is
    # captured by the restic backup below (backup.statePaths contains
    # /var/lib/jellyfin/config), which is what makes that tolerable.
    #
    # Jellyfin's cache - including the transcode scratch that encoding.xml pins
    # to /var/cache/jellyfin/transcodes - is mounted from the 990 PRO rather
    # than left on the root filesystem; see that entry in the nixos-desktop
    # hardware configuration.

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
