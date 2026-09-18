# The networks this configuration treats as "inside": the local network and the
# Tailscale mesh. Two very different consumers share the list, which is why it
# lives on its own rather than inside either of them.
#
#   * layout.nix restricts the *.lan admin vhosts to these ranges, so Caddy's
#     public listener on 80/443 cannot be talked into proxying sonarr.lan & co.
#     by a request that simply sends the right Host header.
#   * ssh.nix and steam.nix open their ports to these ranges only, through the
#     `localOnly` helper below, instead of to every interface.
#
# Add a network here once and both follow; no caller has to know the list.
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
  # and from nowhere else. Meant for networking.firewall.extraCommands, which
  # NixOS runs immediately before the firewall's final reject rule - so these
  # rules are the only thing letting the port through, and the caller must drop
  # the blanket allowedTCPPorts/allowedUDPPorts entry that would have opened it
  # everywhere.
  #
  # Port specs go straight to `-m multiport --dports`, so a range is written the
  # iptables way: "27031:27035". Loopback is skipped because the firewall
  # already trusts the `lo` interface. The IPv6 half is deliberately not covered
  # here: Tailscale traffic arrives on tailscale0 and is allowed with an
  # interface rule instead, and no globally routed IPv6 prefix is ever accepted.
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
