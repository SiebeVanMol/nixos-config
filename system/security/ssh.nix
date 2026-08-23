# OpenSSH server for remote access, hardened for key-only auth, plus fail2ban
# to rate-limit brute-force attempts against SSH and exposed services.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.device.security.ssh.enable {
    services.openssh = {
      enable = true;
      startWhenNeeded = true;

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

    # Ban IPs that repeatedly fail authentication.
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      ignoreIP = ["127.0.0.1/8" "::1/128"];
    };
  };
}
