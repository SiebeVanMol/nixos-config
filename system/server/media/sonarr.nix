# Sonarr: TV acquisition. The service unit, key-permission rule and registry
# entry are built by media.mkArr; only the values that differ are named here.
{
  config,
  lib,
  media,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable (media.mkArr {
    name = "sonarr";
    port = 8989;
    order = 10;
    description = "TV";
    category = "tv-sonarr";
    # Sonarr still calls its project NzbDrone, so that is the directory it nests
    # its config.xml under.
    projectDir = "NzbDrone";
    writePaths = [media.downloads media.shows];
  });
}
