# Radarr: movie acquisition. Built by media.mkArr; see sonarr.nix for the shape.
{
  config,
  lib,
  media,
  ...
}: let
  arrApps = import ../../../lib/arr-apps.nix {inherit lib;};
in {
  config = lib.mkIf config.device.app.jellyfin.enable (media.mkArr (arrApps.mkArrArgs "radarr"
    // {
      writePaths = [media.downloads media.movies];
    }));
}
