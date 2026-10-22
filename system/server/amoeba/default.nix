# amoeba-kernel.org: the Fossil repository of the amoeba kernel, published at the
# apex of its own domain.
#
# The repository file served here is the author's own, not a published copy.
# `fossil server` opens it read-mostly while check-ins write it, and SQLite
# serialises the two, so the site shows a commit the moment it exists. A publish
# step would add a second copy that is stale exactly when someone is looking, and
# a ticket filed against a commit that is already fixed.
#
# Fossil does not know it is behind a proxy, so it has to be told its public base
# URL: without `--baseurl` its timeline builds links to http://127.0.0.1:<port>,
# which is a dead address for everyone but this machine. It listens on loopback
# and only Caddy reaches it, so no port is opened for it - the machine's 80/443
# are already forwarded for the Caddy vhosts, and this repository is deliberately
# not another one of them.
#
# Anonymous visitors get Fossil's default capabilities: read the timeline, wiki
# and tickets, write nothing. Anything that writes needs an account with the
# password set on the repository (`fossil user password`).
#
# The A record for the domain must be **DNS-only** in Cloudflare (grey cloud, not
# orange). Caddy gets its certificate with the ACME HTTP-01 challenge, which
# Caddy answers itself on port 80; with the record proxied, Cloudflare answers
# that challenge (or refuses it) and the certificate never issues - the site then
# serves a Cloudflare error, not this machine. `snowyrenard.com` is set up the
# same way, unproxied, and its certificate lives in `/var/lib/caddy`.
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.device.app.amoeba;
in {
  options.device.app.amoeba = {
    enable = lib.mkEnableOption "the amoeba Fossil repository server";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "amoeba-kernel.org";
      description = "Domain the repository is published on (its apex; www redirects here).";
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "/home/snowyrenard/Documents/Programming/Rust/amoeba.fossil";
      description = ''
        The Fossil repository file to serve. This is the working repository, so
        the check-out's siblings (`amoeba/`) and the mirror script both point at
        the same file; the service must run as the user that owns it.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "snowyrenard";
      description = "User the server runs as. It owns the repository file.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Loopback port Fossil listens on. Caddy proxies to it.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Listening on loopback means the firewall needs nothing: Caddy is the only
    # client, and it is already the public edge of this machine.
    systemd.services.amoeba-fossil = {
      description = "amoeba Fossil repository (${cfg.domain})";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        User = cfg.user;
        ExecStart = lib.escapeShellArgs [
          "${pkgs.fossil}/bin/fossil"
          "server"
          cfg.repository
          "--localhost"
          "--port"
          (toString cfg.port)
          "--baseurl"
          "https://${cfg.domain}"
        ];

        Restart = "on-failure";
        RestartSec = 5;

        # A check-in rewrites the repository file and leaves a journal beside it,
        # so the directory holding it is the one place this service may write.
        # Everything else stays read-only, which also keeps a Fossil bug from
        # touching the check-out that sits next to it.
        ProtectSystem = "strict";
        ReadWritePaths = [(builtins.dirOf cfg.repository)];
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };

    # The vhosts are declared here rather than in the media stack's registry
    # because this site is not one of that stack's services: it has its own
    # domain, not a name under the public domain, so `mkPublicVhost` does not
    # describe it.
    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable {
      "${cfg.domain}".extraConfig = ''
        reverse_proxy 127.0.0.1:${toString cfg.port}
      '';

      "www.${cfg.domain}".extraConfig = ''
        redir https://${cfg.domain}{uri} permanent
      '';
    };
  };
}
