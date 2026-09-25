# Radarr: movie acquisition. Built by media.mkArr; see sonarr.nix for the shape.
{
  config,
  lib,
  media,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable (media.mkArr {
    name = "radarr";
    port = 7878;
    order = 20;
    description = "Movies";
    category = "radarr";
    writePaths = [media.downloads media.movies];
  });
}
