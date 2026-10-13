# The networks this configuration treats as "inside": the local network and the
# Tailscale mesh. Shared by two different consumers:
#   * lib/vhosts.nix restricts the *.lan admin vhosts to these ranges, so Caddy's
#     public listener cannot be talked into proxying sonarr.lan & co. by a
#     request that sends the right Host header.
#   * ssh.nix and steam.nix open their ports to these ranges only, via
#     `localOnly` below, instead of to every interface.
{lib}: rec {
  ipv4 = [
    "127.0.0.0/8" # loopback
    "10.0.0.0/8" # RFC1918
    "172.16.0.0/12" # RFC1918
    "192.168.0.0/16" # RFC1918 - the LAN these machines sit on
    "100.64.0.0/10" # Tailscale, which uses RFC 6598 carrier-grade NAT space
  ];

  ipv6 = [
    "::1/128" # loopback
    "fe80::/10" # link-local, which by construction cannot leave the link
    "fd7a:115c:a1e0::/48" # Tailscale's ULA prefix
  ];

  # For Caddy's remote_ip matcher, which takes both address families in one
  # list.
  all = ipv4 ++ ipv6;

  # iptables commands that accept the given ports from the IPv4 networks above
  # and nowhere else. Meant for networking.firewall.extraCommands, which runs
  # immediately before the final reject rule - so these rules are the only thing
  # letting the port through, and the caller must drop the blanket
  # allowedTCPPorts/allowedUDPPorts entry.
  #
  # Ports go straight to `-m multiport --dports`, so ranges use the iptables form
  # "27031:27035". Loopback is skipped (the firewall already trusts `lo`). IPv6
  # is deliberately not covered: Tailscale arrives on tailscale0 and is allowed
  # with an interface rule, and no globally routed IPv6 prefix is accepted.
  localOnly = {
    tcp ? [],
    udp ? [],
  }:
    lib.concatMapStrings (
      net:
        lib.optionalString (tcp != []) "iptables -w -A nixos-fw -s ${net} -p tcp -m multiport --dports ${lib.concatStringsSep "," tcp} -j nixos-fw-accept\n"
        + lib.optionalString (udp != []) "iptables -w -A nixos-fw -s ${net} -p udp -m multiport --dports ${lib.concatStringsSep "," udp} -j nixos-fw-accept\n"
    ) (lib.remove "127.0.0.0/8" ipv4);
}
