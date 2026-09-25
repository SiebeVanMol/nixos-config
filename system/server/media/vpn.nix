# The WireGuard namespace the media stack's download clients share.
#
# Declared once here rather than inside a particular client, because more than
# one uses it: Transmission and slskd both run confined to `wg0`. Each client
# contributes its own `portMappings` and `openVPNPorts` (list options merge), so
# this file only owns the thing they have in common - the namespace and its
# single ProtonVPN connection. One tunnel, one account login, no matter how
# many clients are added.
#
# The WireGuard config lives at a neutral system path (/etc), not under a
# particular user's home, so nothing depends on which user owns the flake.
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
