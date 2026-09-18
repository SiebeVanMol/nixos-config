# Brute-force protection for the parts of this stack the whole internet can
# reach.
#
# Jellyfin and Seerr are the only two services published on a public domain, and
# they are also the only two with a password prompt in front of them, which makes
# them the only two worth watching. The *arr apps and the rest answer on *.lan
# only, are unreachable from outside (see the guard in
# system/server/jellyfin/layout.nix), and are covered by their own login
# lockout, so no jail is needed for them.
#
# Both jails read Caddy's access logs rather than the applications' own logs, for
# two reasons:
#
#   * Caddy records the real client address. Jellyfin is behind a proxy with no
#     KnownProxies configured, so every request reaching it comes from
#     127.0.0.1 - banning that would ban the whole world, and banning nothing
#     would be equally useless.
#   * The access log is one JSON object per request, so a filter can match the
#     request that failed rather than a follow-up line whose format the
#     application is free to change.
#
# The filters match Caddy's field order (remote_ip, then uri, then status in the
# same object). If a Caddy upgrade ever reorders them, the symptom is simply
# that the jail stops firing; `fail2ban-regex` against the log file shows it
# immediately.
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
  # Two of these ranges matter more than they look. The local network includes
  # the router, and traffic from inside the house that targets the *public* name
  # (a phone on the wifi opening jellyfin.snowyrenard.com) is NATed twice and
  # arrives with the router's LAN address as its client - Caddy's own journal
  # shows 192.168.0.1 for exactly those requests. A ban would therefore be placed
  # on the router, cutting the household off from its own public domains rather
  # than the attacker off from the site. Loopback and Tailscale are excluded for
  # the same reason: they are already trusted, and a guess that fails from inside
  # is not an attack worth locking anyone out over.
  #
  # It has to live inside `settings`, not beside it: the jail submodule only
  # passes `enabled`, `filter` and `settings` through to jail.local, and a
  # stray key elsewhere is dropped without complaint. Setting it here overrides
  # the global ignoreip for these two jails only, so the sshd jail keeps banning
  # attackers wherever they come from.
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
          # A rejected sign-in is a 401 from /Users/AuthenticateByName; a
          # successful one is a 200 from the same endpoint.
          #
          # The threshold is deliberately loose: a client whose saved password has
          # gone stale retries on its own, and locking a household out of Jellyfin
          # for an hour is a worse outcome than letting a slow guessing attack
          # continue a little longer. Anyone actually guessing needs far more than
          # ten attempts.
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
