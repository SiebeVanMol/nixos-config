# The reverse proxy surface: one Caddy virtual host per registered service, and
# the hosts-file entries that make the *.lan names resolve here.
#
# Nothing is listed by hand any more. A service that registers itself in
# device.media.services gets a *.lan vhost (and, with `public = true`, a HTTPS
# one on the public domain) without this file changing. The LAN-only guard
# itself lives in lib/vhosts.nix so it cannot drift from any other stack's.
{
  config,
  lib,
  ...
}: let
  vhosts = import ../../../lib/vhosts.nix {inherit lib config;};

  # `name` is the registry key; the rest of the entry is the service's own
  # description of itself.
  sites = lib.mapAttrsToList (name: site: site // {inherit name;}) config.device.media.services;

  lanHosts = map (site: "${site.name}.lan") sites;
in {
  config = lib.mkIf config.device.media.enabled {
    # *.lan is plain HTTP for the local network; a service marked public also
    # gets an HTTPS subdomain for friends.
    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable (lib.listToAttrs (
      (map vhosts.mkLanVhost sites)
      ++ lib.optionals (config.device.security.reverse-proxy.publicDomain != "") (
        map vhosts.mkPublicVhost (lib.filter (site: site.public) sites)
      )
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
        "127.0.0.1" = lanHosts;
      })
    ];
  };
}
