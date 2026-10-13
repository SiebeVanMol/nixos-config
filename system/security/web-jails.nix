# Brute-force protection for the parts of this stack the whole internet can reach.
#
# Jellyfin, Seerr and Navidrome are published on a public domain; the two filters
# below cover Jellyfin and Seerr, and a newly published service gets its own jail
# the same way. The *arr apps answer on *.lan only (see lib/vhosts.nix) and have
# their own lockout, so they need no jail.
#
# Both read Caddy's access log rather than the app's own, because Caddy records
# the real client address (Jellyfin is behind a proxy with no KnownProxies, so
# every request it sees comes from 127.0.0.1) and because one JSON object per
# request lets a filter match the failed request itself. The filters match
# Caddy's field order (remote_ip, uri, status); if a Caddy upgrade reorders them
# the jail silently stops firing, and `fail2ban-regex` shows it.
{
  config,
  lib,
  ...
}: let
  domain = config.device.security.reverse-proxy.publicDomain;

  # What counts as "inside". Used to keep these jails from banning the household
  # or the router - see the ignoreip note below.
  internalNetworks = import ../../lib/internal-networks.nix {inherit lib;};

  # The NixOS Caddy module writes one access log per virtual host, named after
  # the vhost.
  logPath = name: "/var/log/caddy/access-${name}.${domain}.log";

  # Addresses these jails must never ban.
  #
  # The local network includes the router, and traffic from inside the house to
  # the *public* name is NATed twice and arrives with the router's LAN address as
  # its client - Caddy's journal shows 192.168.0.1 for exactly those. Banning it
  # would cut the household off rather than the attacker. Loopback and Tailscale
  # are already trusted.
  #
  # Must live inside `settings`: the jail submodule only passes `enabled`,
  # `filter` and `settings` through to jail.local, and a stray key is dropped
  # silently. Setting it here overrides the global ignoreip for these two jails
  # only, so the sshd jail keeps banning attackers wherever they come from.
  ignoreip = lib.concatStringsSep " " internalNetworks.all;
in {
  config =
    lib.mkIf (
      config.device.app.jellyfin.enable
      && config.device.security.reverse-proxy.enable
      && domain != ""
    ) {
      services.fail2ban = {
        enable = true;

        jails = {
          # A rejected sign-in is a 401 from /Users/AuthenticateByName; a success
          # is a 200. The threshold is deliberately loose: a client with a stale
          # saved password retries on its own, and locking the household out for
          # an hour is worse than letting a slow guessing attack continue.
          jellyfin-login = {
            filter = {
              Definition = {
                failregex = ''^.*"remote_ip":"<HOST>".*"uri":"/Users/AuthenticateByName".*"status":401.*$'';
              };
            };
            settings = {
              logpath = logPath "jellyfin";
              # The global default backend is systemd, which would read the
              # journal; these are files, so read them as files.
              backend = "auto";
              # The ban action blocks ports, and fail2ban's own default is ssh.
              # Block the web ports instead: an attacker guessed at a website, so
              # that is what they should lose.
              port = "http,https";
              inherit ignoreip;
              maxretry = 10;
              findtime = "10m";
              bantime = "1h";
            };
          };

          # Seerr answers a wrong password with 403 "Access denied." on its local
          # login endpoint. Nothing retries this one automatically, so it can be
          # watched more tightly than Jellyfin.
          seerr-login = {
            filter = {
              Definition = {
                failregex = ''^.*"remote_ip":"<HOST>".*"uri":"/api/v1/auth/local".*"status":403.*$'';
              };
            };
            settings = {
              logpath = logPath "seerr";
              backend = "auto";
              port = "http,https";
              inherit ignoreip;
              maxretry = 5;
              findtime = "10m";
              bantime = "1h";
            };
          };
        };
      };
    };
}
