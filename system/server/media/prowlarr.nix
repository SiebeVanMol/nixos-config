# Prowlarr: the indexer manager that feeds the *arr applications.
{
  config,
  lib,
  media,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable {
    services.prowlarr.enable = true;

    # Prowlarr only searches indexers and hands results to the applications; it
    # never touches the library, so it gets no /Vault write path.
    systemd.services.prowlarr.serviceConfig = media.vaultRw [];

    device.media.services.prowlarr = {
      port = 9696;
      dashboard = {
        group = "acquisition";
        order = 40;
        title = "Prowlarr";
        description = "Indexers";
        widget = {
          type = "prowlarr";
          keyVar = "HOMEPAGE_VAR_PROWLARR_KEY";
        };
      };
      backup = {
        sqliteRoots = ["/var/lib/prowlarr"];
        statePaths = ["/var/lib/prowlarr/config.xml"];
      };
    };
  };
}
