# Lidarr: music acquisition. Built by media.mkArr; see sonarr.nix for the shape.
{
  config,
  lib,
  media,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable (media.mkArr {
    name = "lidarr";
    port = 8686;
    order = 30;
    description = "Music";
    category = "lidarr";
    # Two sources feed it: Transmission (torrents, via /Vault/Downloads) and
    # Soularr, which has slskd drop finished Soulseek downloads in
    # /Vault/Media/downloads and then calls Lidarr's import API.
    writePaths = [media.downloads media.musicDownloads media.musicLibrary];
  });
}
