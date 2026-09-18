# OpenSSH server for remote access, hardened for key-only auth, plus fail2ban
# to rate-limit brute-force attempts against SSH and exposed services.
{
  config,
  lib,
  ...
}: let
  internalNetworks = import ../../lib/internal-networks.nix {inherit lib;};
in {
  config = lib.mkIf config.device.security.ssh.enable {
    services.openssh = {
      enable = true;
      startWhenNeeded = true;

      # The module's default would open port 22 on every interface. The router
      # does not forward it today, but a router configuration change or a stray
      # UPnP request should not be able to put an SSH daemon on the internet:
      # the rules below open it to the local network and the Tailscale mesh
      # only, which is also how this host is meant to be reached from outside.
      openFirewall = false;

      settings = {
        # Key-based authentication only.
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";

        # Limit brute-force attempts and keep verbose logs.
        MaxAuthTries = 3;
        LogLevel = "VERBOSE";

        # Surface area reduction.
        X11Forwarding = false;
        AllowAgentForwarding = false;
        PermitEmptyPasswords = false;
      };
    };

    # SSH from the local network, plus anything arriving over Tailscale, which
    # the interface rule covers for both address families. Together with
    # `openFirewall = false` above that makes port 22 unreachable from the
    # internet.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [22];
    networking.firewall.extraCommands = internalNetworks.localOnly {
      tcp = ["22"];
    };

    # Ban IPs that repeatedly fail authentication.
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      ignoreIP = ["127.0.0.1/8" "::1/128"];
    };
  };
}
