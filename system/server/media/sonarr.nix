# Sonarr: TV acquisition. The service unit, key-permission rule and registry
# entry are built by media.mkArr; only the values that differ are named here.
{
  config,
  lib,
  media,
  ...
}: let
  arrApps = import ../../../lib/arr-apps.nix {inherit lib;};
in {
  config = lib.mkIf config.device.app.jellyfin.enable (media.mkArr (arrApps.mkArrArgs "sonarr"
    // {
      writePaths = [media.downloads media.shows];
    }));
}
