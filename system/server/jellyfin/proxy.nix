# The reverse proxy surface: one Caddy virtual host per service, and the
# hosts-file entries that make the *.lan names resolve here.
{
  config,
  lib,
  ...
}: let
  stack = import ./layout.nix {inherit config lib;};
in {
  config = lib.mkIf stack.enabled {
    # Reverse proxy every service on its own subdomain.
    # *.lan is plain HTTP for the local network; only Jellyfin and Seerr get a
    # public HTTPS subdomain on *.${publicDomain} for friends.
    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable (lib.listToAttrs (
      (map stack.mkLanVhost stack.activeSites)
      ++ lib.optionals (config.device.security.reverse-proxy.publicDomain != "") (map stack.mkPublicVhost stack.publicSites)
    ));

    networking.hosts = lib.mkMerge [
      {
        # 1337x sits behind Cloudflare, and Prowlarr's FlareSolverr proxy has to
        # reach the site's origin addresses; pinning them here keeps that
        # working when the resolver hands back something else.
        "172.67.188.67" = ["1337x.to"];
        "104.21.40.193" = ["1337x.to"];
      }
      (lib.mkIf config.device.security.reverse-proxy.enable {
        "127.0.0.1" = stack.lanHosts;
      })
    ];
  };
}
