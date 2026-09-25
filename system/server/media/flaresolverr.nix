# FlareSolverr: the Cloudflare bypass one of Prowlarr's indexers needs.
{
  config,
  lib,
  media,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # Bypass Cloudflare on protected indexers (e.g. 1337x). Prowlarr is pointed
    # at http://127.0.0.1:8191 as a FlareSolverr proxy.
    services.flaresolverr.enable = true;

    # It only answers HTTP requests; no /Vault access at all.
    systemd.services.flaresolverr.serviceConfig = media.vaultRw [];

    device.media.services.flaresolverr = {
      port = 8191;
      # A management endpoint with no login behind it: never public. It is not
      # a library tile either, so it renders as an admin bookmark.
      dashboard = {
        group = "admin";
        order = 10;
        title = "FlareSolverr";
        abbr = "FS";
      };
    };
  };
}
