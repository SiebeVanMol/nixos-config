# Torrenting: Transmission, confined to the WireGuard namespace so its traffic
# cannot leave except through the VPN.
#
# The namespace itself is declared here because Transmission is what it exists
# for; the `sites` entry that publishes its RPC and the download clients the
# *arr apps use both point at `vpnNamespaces.wg0.namespaceAddress` rather than
# 127.0.0.1, since locally generated traffic never traverses PREROUTING and so
# cannot reach the forwarded port.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stack = import ./layout.nix {inherit config lib;};
in {
  config = lib.mkIf stack.enabled {
    systemd.services.transmission = {
      serviceConfig = stack.vaultRw ["/Vault/Downloads"];
      # Attach the transmission systemd service to the VPN namespace.
      vpnConfinement = {
        enable = true;
        vpnNamespace = "wg0";
      };
    };

    # VPN namespace for torrenting. The WireGuard config lives at a neutral
    # system path (/etc), not under a particular user's home, so nothing depends
    # on which user owns the flake.
    vpnNamespaces.wg0 = {
      enable = true;
      wireguardConfigFile = "/etc/wireguard/wg0.conf";
      portMappings = [
        {
          from = 9091;
          to = 9091;
        }
      ];
    };

    # Torrenting
    services.transmission = {
      enable = true;
      group = "users";
      package = pkgs.transmission_4;
      settings = {
        download-dir = "/Vault/Downloads";
        incomplete-dir = "/Vault/Downloads/.incomplete";
        incomplete-dir-enabled = true;
        umask = "002";
        rpc-bind-address = "0.0.0.0";
        rpc-whitelist-enabled = false;
        # Stop seeding once a torrent's share ratio hits 0.00 (right after
        # download completes). Uses the kebab-case keys Transmission 4 honors.
        "ratio-limit" = 0;
        "ratio-limit-enabled" = true;
        # Also stop seeding if a torrent is idle for 0 minutes.
        "idle-seeding-limit" = 0;
        "idle-seeding-limit-enabled" = true;
      };
    };
  };
}
