# OpenSSH: the server side is key-only auth plus fail2ban to rate-limit
# brute-force attempts, and that part is off unless device.security.ssh.enable
# is set. The client side below is not a toggle and applies to every host.
{
  config,
  lib,
  ...
}: let
  internalNetworks = import ../../lib/internal-networks.nix {inherit lib;};

  # nixpkgs writes two `Include` lines into ssh_config, one pointing into the
  # libvirt store path and one into systemd's. OpenSSH refuses to read a config
  # file owned by neither root nor the invoking user, and inside a user
  # namespace - which is where the DeepSeek Harness sandbox runs every command -
  # the host's uid 0 is not mapped, so those root-owned store files appear to be
  # owned by `nobody` and every ssh invocation dies before it connects:
  #
  #   Bad owner or permissions on
  #     /nix/store/...-libvirt-.../etc/ssh/ssh_config.d/30-libvirt-ssh-proxy.conf
  #
  # Both fragments are short and self-contained (neither has Includes of its
  # own), so their text is emitted inline instead of being Included by path. The
  # directives are identical; they just arrive as part of a file OpenSSH does
  # not ownership-check, which makes ssh work the same in and out of a
  # namespace. Keeping the settings rather than dropping them matters: the
  # libvirt fragment is what makes `ssh qemu:///system/<vm>` reach a guest, and
  # systemd's is what makes `.host`, `machine/*` and `unix/*` resolve.
  #
  # Both readFiles are lazy, so on a host without virtualisation the libvirt
  # fragment is never evaluated and libvirt stays out of that host's closure.
  libvirtSshProxy = builtins.readFile "${config.virtualisation.libvirtd.package}/etc/ssh/ssh_config.d/30-libvirt-ssh-proxy.conf";
  systemdSshProxy = builtins.readFile "${config.systemd.package}/lib/systemd/ssh_config.d/20-systemd-ssh-proxy.conf";
in {
  config = lib.mkMerge [
    {
      # Drop both Include lines, since their targets cannot be read from inside
      # a user namespace; the fragments' contents are re-added just below.
      virtualisation.libvirtd.sshProxy = false;

      programs.ssh = {
        systemd-ssh-proxy.enable = false;
        extraConfig = lib.mkAfter (
          (lib.optionalString config.device.app.virtualization.enable libvirtSshProxy)
          + systemdSshProxy
        );
      };
    }

    (lib.mkIf config.device.security.ssh.enable {
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
    })
  ];
}
