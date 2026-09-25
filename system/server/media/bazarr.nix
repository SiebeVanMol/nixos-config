# Bazarr: subtitles.
{
  config,
  lib,
  media,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable {
    services.bazarr = {
      enable = true;
      group = "users";
    };

    # Subtitles are written next to the library media, wherever it is; it reads
    # downloads too.
    systemd.services.bazarr.serviceConfig = media.vaultRw [media.mediaRoot media.downloads];

    device.media.services.bazarr = {
      port = 6767;
      dashboard = {
        group = "acquisition";
        order = 50;
        title = "Bazarr";
        description = "Subtitles";
        widget = {
          type = "bazarr";
          keyVar = "HOMEPAGE_VAR_BAZARR_KEY";
        };
      };
      # 1.6 moved settings from config.ini to config.yaml; the whole config
      # directory is copied either way.
      backup = {
        sqliteRoots = ["/var/lib/bazarr"];
        statePaths = ["/var/lib/bazarr/config"];
      };
    };
  };
}
