# Torrenting: Transmission, confined to the WireGuard namespace so its traffic
# cannot leave except through the VPN. The namespace is declared in vpn.nix and
# shared with slskd; this file only adds Transmission's port mapping. The RPC
# vhost and the *arr download clients point at the veth address, not 127.0.0.1,
# because locally generated traffic never traverses PREROUTING.
{
  config,
  lib,
  pkgs,
  media,
  ...
}: let
  rpcPort = 9091;

  # The port peers use to reach this client. Must match what ProtonVPN forwards
  # for the session to actually accept inbound connections.
  peerPort = 51413;
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    systemd.services.transmission = {
      serviceConfig = media.vaultRw [media.downloads];
      # Attach the transmission systemd service to the VPN namespace.
      vpnConfinement = {
        enable = true;
        vpnNamespace = "wg0";
      };
    };

    # Open the RPC port into the namespace for the host's reverse proxy. The
    # namespace and its WireGuard config are declared in vpn.nix.
    vpnNamespaces.wg0.portMappings = [
      {
        from = rpcPort;
        to = rpcPort;
      }
    ];

    # Let peers connect *in*. The namespace INPUT policy DROPs everything, so
    # without this a well-seeded torrent can sit at "stalled, 0 peers" forever.
    # The port is opened on the tunnel interface, so only via the VPN.
    #
    # ProtonVPN hands out its forwarded port dynamically (NAT-PMP), so this only
    # fully works once `peerPort` matches the VPN's port for the session.
    vpnNamespaces.wg0.openVPNPorts = [
      {
        port = peerPort;
        protocol = "both";
      }
    ];

    # Torrenting
    services.transmission = {
      enable = true;
      group = "users";
      package = pkgs.transmission_4;
      settings = {
        download-dir = media.downloads;
        incomplete-dir = "${media.downloads}/.incomplete";
        incomplete-dir-enabled = true;
        umask = "002";
        rpc-bind-address = "0.0.0.0";
        rpc-whitelist-enabled = false;
        # Transmission 4 answers 421 to any Host header it does not recognise.
        # That DNS-rebinding guard is separate from rpc-whitelist: disabling the
        # IP whitelist does NOT let a hostname through. Leaving it unset is
        # confusing - Caddy serves the UI fine but every RPC behind it fails, so
        # the page looks broken rather than forbidden.
        #
        # COMMA-SEPARATED STRING, not a list: a JSON array is silently dropped
        # back to "" and every hostname keeps being rejected.
        rpc-host-whitelist-enabled = true;
        rpc-host-whitelist = "transmission.lan,127.0.0.1,localhost";
        # The peer port opened on the VPN interface above. Fixed rather than
        # random so the rule stays valid across restarts; set it to the port
        # ProtonVPN currently forwards for the session if the two differ.
        peer-port = peerPort;
        peer-port-random-on-start = false;
        # Let Transmission ask the gateway for a port via NAT-PMP; without it
        # there is no inbound route even when a port is forwarded on the VPN.
        port-forwarding-enabled = true;
        # Stop seeding once a torrent's share ratio hits 0.00 (right after
        # download completes). Uses the kebab-case keys Transmission 4 honors.
        "ratio-limit" = 0;
        "ratio-limit-enabled" = true;
        # Also stop seeding if a torrent is idle for 0 minutes.
        "idle-seeding-limit" = 0;
        "idle-seeding-limit-enabled" = true;
        # No download queue: the default of five concurrent downloads with the
        # rest in download-wait relies on queue-stalled-minutes, which falls apart
        # when stalls are the norm - fifty torrents queued behind five that never
        # found a peer, while a well-seeded control sat in download-wait for
        # ninety seconds. With this off it completed at 51 MB/s. Resource use is
        # bounded by the global peer limit, not the active torrent count.
        "download-queue-enabled" = false;
      };
    };

    device.media.services.transmission = {
      port = rpcPort;
      # Its RPC socket is inside the namespace, so Caddy has to address the
      # veth peer rather than loopback.
      host = config.vpnNamespaces.wg0.namespaceAddress;
      dashboard = {
        group = "downloads";
        order = 10;
        title = "Transmission";
        description = "Torrents";
        widget = {
          type = "transmission";
          url = "http://${config.vpnNamespaces.wg0.namespaceAddress}:${toString rpcPort}";
        };
      };
      backup.statePaths = ["/var/lib/transmission/.config/transmission-daemon"];
    };
  };
}
