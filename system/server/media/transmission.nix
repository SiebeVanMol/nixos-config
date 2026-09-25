# Torrenting: Transmission, confined to the WireGuard namespace so its traffic
# cannot leave except through the VPN.
#
# The namespace itself is declared once in vpn.nix and shared with slskd; this
# file only contributes Transmission's own port mapping. The RPC vhost and the
# *arr download clients both point at the namespace's veth address rather than
# 127.0.0.1, since locally generated traffic never traverses PREROUTING and so
# cannot reach the forwarded loopback port.
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

    # Let peers connect *in*, not just out. The namespace's INPUT policy DROPs
    # everything, so without this a torrent with plenty of seeders can still sit
    # at "stalled, 0 peers" forever - which is exactly what the queue showed.
    # The port is opened on the tunnel interface, so it is only reachable
    # through the VPN.
    #
    # ProtonVPN hands out its forwarded port dynamically (NAT-PMP), so this only
    # becomes fully useful once `peerPort` matches the port the VPN reports for
    # the current session; see the note in the settings below.
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
        # Transmission 4 refuses any request whose Host header it does not
        # recognise, answering 421 Misdirected Request. That protection exists
        # to stop DNS rebinding, and it is separate from the rpc-whitelist
        # above: disabling the IP whitelist does NOT let a hostname through.
        #
        # The consequence of leaving it alone is confusing, because the web UI
        # is served by Caddy and loads perfectly - it is every RPC call behind
        # it that fails, so the page comes up empty and looks broken rather than
        # forbidden. The reverse-proxy name therefore has to be listed here.
        #
        # COMMA-SEPARATED STRING, not a list. Transmission's own rewritten
        # settings.json shows "rpc-whitelist": "127.0.0.1,::1", and feeding it a
        # JSON array does not error - it silently drops the value back to "" and
        # keeps rejecting every hostname, which looks exactly like the setting
        # never having been applied.
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
        # No download queue.
        #
        # Transmission's default is five concurrent downloads with the rest held
        # in "download-wait", relying on `queue-stalled-minutes` to rotate the
        # stalled ones out. That falls apart when stalls are the norm rather
        # than the exception: with fifty-odd torrents queued behind five that
        # never found a peer, nothing else ever attempted a connection, and the
        # whole library looked dead while the client, the tunnel and the
        # indexers were all working. A control torrent with thousands of
        # seeders sat in download-wait for ninety seconds without trying; with
        # this off it completed at 51 MB/s.
        #
        # Letting every torrent look for peers at once is the point. What
        # bounds resource use is Transmission's global peer limit, not the
        # number of active torrents.
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
