# Caddy virtual-host constructors shared by every service that publishes itself
# through the reverse proxy.
#
# They live here, rather than inside one stack, because the LAN-only guard below
# is a security property: two copies of it would eventually drift, and the copy
# that drifted is the one that lets the internet reach an admin UI by sending
# the right Host header. Any stack can call these with its own registry entries.
{
  lib,
  config,
}: rec {
  internalNetworks = import ./internal-networks.nix {inherit lib;};

  # Where a vhost sends its traffic: unset lands on loopback, while a service in
  # a VPN namespace sets the namespace's veth address, because locally generated
  # traffic never traverses PREROUTING and cannot reach a forwarded loopback port.
  upstream = site: let
    host =
      if site.host != null
      then site.host
      else "127.0.0.1";
  in "${host}:${toString site.port}";

  # Public vhost: a plain reverse proxy, with automatic HTTPS via the HTTP-01
  # challenge.
  mkPublicVhost = site: {
    name = "${site.name}.${config.device.security.reverse-proxy.publicDomain}";
    value.extraConfig = "reverse_proxy ${upstream site}";
  };

  # LAN vhost: the same proxy, but only for clients that are really inside.
  #
  # Ports 80/443 are forwarded from the internet - that is how the public vhosts
  # get certificates - and Caddy picks a vhost from the Host header alone, so
  # unprotected `curl -H 'Host: flaresolverr.lan' http://<public ip>/v1` reaches
  # it from anywhere. remote_ip keeps all *.lan vhosts to the local network and
  # the Tailscale mesh; anything else is refused before reaching a service.
  mkLanVhost = site: {
    name = "http://${site.name}.lan";
    value.extraConfig = ''
      @internal remote_ip ${lib.concatStringsSep " " internalNetworks.all}
      handle @internal {
        reverse_proxy ${upstream site}
      }
      handle {
        respond "This service is only reachable from the local network." 403
      }
    '';
  };
}
