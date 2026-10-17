# Caddy reverse proxy for LAN (plain HTTP) and public HTTPS services.
# Virtual hosts are declared by the stacks that publish through it: the media
# stack derives them from its service registry (system/server/media/proxy.nix).
# This module just enables the Caddy service itself.
{
  config,
  lib,
  ...
}: {
  # This module's file name (reverse-proxy.nix) is its toggle, so `enable` is
  # derived from the tree in system/options.nix. publicDomain is configuration
  # rather than a toggle, so it is declared here with everything else about the
  # proxy.
  options.device.security.reverse-proxy.publicDomain = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Public domain served by the reverse proxy (e.g. snowyrenard.com). Empty = LAN-only.";
  };

  config = lib.mkIf config.device.security.reverse-proxy.enable {
    services.caddy = {
      enable = true;
      openFirewall = true;
    };

    # Port 80 must be open for the HTTP-01 ACME challenge (Caddy already
    # listens there; openFirewall covers it, listed for clarity).
    networking.firewall.allowedTCPPorts = lib.mkIf config.device.security.firewall.enable [80 443];

    # Caddy listens on UDP/443 for HTTP/3 too, but services.caddy.openFirewall
    # opens only the TCP ports, so QUIC answered nothing from outside: every
    # client fell back to TCP without anyone noticing. That costs exactly where
    # it hurts - a client far from this house. HTTP/2 carries the interface and
    # the stream over one TCP connection, so a single lost packet stalls both,
    # and at a quarter-second round trip the window in flight cannot fill the
    # link; QUIC recovers per stream and keeps the rest moving. Verified by
    # measurement, not assumption: `curl --http3-only` to an outside host
    # answers proto=3 from here, the same request to a public vhost times out.
    networking.firewall.allowedUDPPorts = lib.mkIf config.device.security.firewall.enable [443];
  };
}
