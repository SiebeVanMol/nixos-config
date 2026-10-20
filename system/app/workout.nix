# The evening workout app: a loopback web server (127.0.0.1:8787) that Snowy
# starts in his own user session. This module gives it a name to open instead of
# an address and a port.
#
# workout.localhost is published alongside workout.lan on purpose: browsers
# resolve *.localhost to loopback on their own (RFC 6761), so that URL works even
# before the hosts entry exists, and it reads better on this machine.
{
  config,
  lib,
  ...
}: let
  internalNetworks = import ../../lib/internal-networks.nix {inherit lib;};

  # The same LAN-only guard lib/vhosts.nix applies to the media vhosts. Ports 80
  # and 443 are forwarded from the internet so the public vhosts can get
  # certificates, and Caddy picks a vhost from the Host header alone - without
  # this, `curl -H 'Host: workout.lan' http://<public ip>/` would reach the app
  # from anywhere.
  guarded = ''
    @internal remote_ip ${lib.concatStringsSep " " internalNetworks.all}
    handle @internal {
      reverse_proxy 127.0.0.1:8787
    }
    handle {
      respond "This service is only reachable from the local network." 403
    }
  '';
in {
  options.device.app.workout.enable =
    lib.mkEnableOption "the evening workout app's Caddy vhost";

  config = lib.mkIf (config.device.app.workout.enable && config.device.security.reverse-proxy.enable) {
    services.caddy.virtualHosts = {
      "http://workout.lan" = {extraConfig = guarded;};
      "http://workout.localhost" = {extraConfig = guarded;};
    };

    networking.hosts."127.0.0.1" = ["workout.lan"];
  };
}
