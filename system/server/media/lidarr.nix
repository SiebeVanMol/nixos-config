# Lidarr: music acquisition. Built by media.mkArr; see sonarr.nix for the shape.
{
  config,
  lib,
  media,
  ...
}: let
  arrApps = import ../../../lib/arr-apps.nix {inherit lib;};
in {
  config = lib.mkIf config.device.app.jellyfin.enable (media.mkArr (arrApps.mkArrArgs "lidarr"
    // {
      # Two sources feed it: Transmission (torrents, via /Vault/Downloads) and
      # Soularr, which has slskd drop finished Soulseek downloads in
      # /Vault/Media/downloads and then calls Lidarr's import API.
      writePaths = [media.downloads media.musicDownloads media.musicLibrary];
    }));
}
