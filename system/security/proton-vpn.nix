# WireGuard tools for the ProtonVPN tunnel.
#
# The tunnel itself is declared by the media stack (system/server/media/vpn.nix)
# from a static /etc/wireguard/wg0.conf, so `wg`/`wg-quick` are all that is
# needed to inspect or manage it. The official `proton-vpn` CLI is not installed:
# it manages its own connections rather than this declarative tunnel.
{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.device.security.proton-vpn.enable {
    environment.systemPackages = [pkgs.wireguard-tools];
  };
}
