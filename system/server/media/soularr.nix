# Soularr: the bridge that lets Lidarr acquire from Soulseek.
#
# Lidarr has no Soulseek support, so without this slskd downloads bypass it.
# Soularr reads Lidarr's wanted/missing albums, drives slskd's API to search and
# download, then asks Lidarr to import the finished files. It is deliberately NOT
# confined to wg0: it only talks to slskd over the namespace veth and to Lidarr
# on loopback. A oneshot on a timer, like servarr-sync; its config holds two API
# keys, so it is generated into /etc at activation, never the store.
{
  config,
  lib,
  pkgs,
  media,
  ...
}: let
  arrKey = import ../../../lib/arr-api-key.nix {inherit pkgs;};

  configDir = "/etc/soularr";
  configFile = "${configDir}/config.ini";

  writeConfig = pkgs.writers.writePython3Bin "soularr-config" {
    flakeIgnore = ["E501"];
  } (builtins.readFile ./soularr-config.py);

  # The two addresses Soularr reaches: Lidarr on loopback, slskd at the wg0
  # veth peer (its socket lives inside the namespace, so the host cannot use
  # loopback for it - see lib/vhosts.nix for the same reasoning).
  lidarrUrl = "http://127.0.0.1:8686";
  slskdUrl = "http://${config.vpnNamespaces.wg0.namespaceAddress}:5030";
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # The overlay that builds `pkgs.soularr` is applied here rather
    # than to the whole host from flake.nix: it is needed exactly where this
    # service is enabled, so a machine without the media stack never evaluates the
    # pin. The flake still exposes the package as `.#soularr` for nix-update.
    nixpkgs.overlays = [(import ../../../overlays/soularr.nix)];
    users.users.soularr = {
      isSystemUser = true;
      group = "users";
    };

    # Both API keys are read at activation from the applications that own them,
    # so a regenerated key is picked up on the next switch and neither secret is
    # ever written into the store. `slskd-env` creates the slskd key, so it has
    # to run first.
    system.activationScripts.soularr-config = {
      # `users` for the ownership below: the file is handed to the service's own
      # account, so that account has to exist first.
      deps = ["slskd-env" "users"];
      text = ''
        lidarr_key="$(${arrKey}/bin/arr-api-key /var/lib/lidarr 2>/dev/null || true)"
        slskd_key="$(${pkgs.gnused}/bin/sed -n 's/^SLSKD_API_KEY=//p' \
          /etc/slskd/slskd.env 2>/dev/null | ${pkgs.coreutils}/bin/head -n 1)"

        # Before either application has written its key there is nothing to
        # converge; the next switch fills it in.
        if [ -n "$lidarr_key" ] && [ -n "$slskd_key" ]; then
          ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g users ${configDir}
          # The keys go in the environment, not the command line: a root
          # process's environment is readable only by root, while its argv is
          # readable by every local user (/proc/<pid>/cmdline).
          LIDARR_API_KEY="$lidarr_key" SLSKD_API_KEY="$slskd_key" \
            ${writeConfig}/bin/soularr-config \
            ${pkgs.soularr}/share/soularr/config.ini \
            "${configFile}.new" \
            "${lidarrUrl}" \
            "${slskdUrl}" \
            "${media.musicDownloads}"
          # Owned by the service rather than readable by the whole `users`
          # group, which is every media service and both human accounts.
          ${pkgs.coreutils}/bin/install -m 0400 -o soularr -g users "${configFile}.new" "${configFile}"
          ${pkgs.coreutils}/bin/rm -f "${configFile}.new"
        fi
      '';
    };

    systemd.services.soularr = {
      description = "Download Lidarr's wanted albums from Soulseek via slskd";
      after = ["lidarr.service" "slskd.service" "network-online.target"];
      wants = ["lidarr.service" "slskd.service" "network-online.target"];
      serviceConfig =
        {
          Type = "oneshot";
          User = "soularr";
          Group = "users";
          StateDirectory = "soularr";
          ExecStart = "${lib.getExe pkgs.soularr} --config-dir ${configDir} --var-dir /var/lib/soularr";
        }
        // media.vaultRw [media.musicDownloads]
        // {
          # Soularr renames completed download folders before handing them to
          # Lidarr, so it writes the staging directory; it never writes the
          # library itself, which is Lidarr's job.
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictSUIDSGID = true;
        };
    };

    systemd.timers.soularr = {
      wantedBy = ["timers.target"];
      timerConfig = {
        # Every ten minutes, which is what the upstream Docker image uses by
        # default. This is a convergence job, so nothing depends on it being
        # instant; an import simply lands within the next run.
        OnCalendar = "*:0/10";
        Persistent = true;
      };
    };
  };
}
