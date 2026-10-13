# The WireGuard namespace the media stack's download clients share.
#
# Declared once because Transmission and slskd both use it; each client
# contributes its own portMappings/openVPNPorts (lists merge) and this file owns
# only the namespace and its single ProtonVPN connection - one tunnel, one
# account login. The config lives at /etc/wireguard/wg0.conf, a neutral path, so
# nothing depends on which user owns the flake.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.device.media.enabled {
    vpnNamespaces.wg0 = {
      enable = true;
      wireguardConfigFile = "/etc/wireguard/wg0.conf";
    };
  };
}
