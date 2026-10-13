# Caddy reverse proxy for LAN (plain HTTP) and public HTTPS services.
# Virtual hosts are declared by the stacks that publish through it: the media
# stack derives them from its service registry (system/server/media/proxy.nix).
# This module just enables the Caddy service itself.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.device.security.reverse-proxy.enable {
    services.caddy = {
      enable = true;
      openFirewall = true;
    };

    # Port 80 must be open for the HTTP-01 ACME challenge (Caddy already
    # listens there; openFirewall covers it, listed for clarity).
    networking.firewall.allowedTCPPorts = lib.mkIf config.device.security.firewall.enable [80 443];
  };
}
