# Declarative settings sync for the Servarr stack (see servarr-sync.py).
#
# The rest of this directory declares which services run; this module converges
# the settings inside them, which until now were a manual checklist: the download
# client each application uses, the applications Prowlarr pushes its indexers to,
# the notification target, and SeerrNG's links to all of them.
#
# That is several web-UI sessions, replicated across every application, that
# silently rot when a path, port or key changes. Here it is a oneshot that runs
# after the services come up and every morning afterwards.
#
# Two things keep this safe to run unattended:
#
#   * It never writes a secret into the Nix store. The script reads each
#     application's API key at runtime from that application's own config.xml,
#     so the JSON below carries only ports, hostnames and paths.
#   * Every write is a create-or-converge: the live value is compared first and
#     identical settings are left untouched, so a repeat run is a no-op.
#
# Indexers themselves are deliberately NOT declared. Adding one means supplying
# that tracker's credentials, which are personal secrets and change per site;
# Prowlarr's own UI is the right place for them. What this does is make sure the
# applications Prowlarr pushes to, and the download client each of them uses,
# are correct without anyone clicking.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # These ports mirror the `sites` list in jellyfin.nix and the per-category
  # download directories mirror the tmpfiles rules there; if either moves, move
  # it in both places.
  apps = {
    sonarr = {
      port = 8989;
      dir = "/var/lib/sonarr";
      implementation = "Sonarr";
      category = "tv-sonarr";
    };
    radarr = {
      port = 7878;
      dir = "/var/lib/radarr";
      implementation = "Radarr";
      category = "radarr";
    };
    lidarr = {
      port = 8686;
      dir = "/var/lib/lidarr";
      implementation = "Lidarr";
      category = "lidarr";
    };
  };

  prowlarr = {
    port = 9696;
    dir = "/var/lib/prowlarr";
  };

  # The indexers Prowlarr searches. These values are not invented: they are
  # exactly what `nix run .#servarr-export` read back from the live instance, so
  # the first convergence run is a no-op and this list simply makes the current
  # state recoverable. The `info_*` fields the API also returns are left out on
  # purpose - those are the definition's own help text, which Prowlarr fills in
  # itself and which changes with the definition.
  #
  # None of these four needs a credential (they are all public Cardigann
  # trackers); a private tracker would add its login through the root-only
  # secrets file rather than here.
  indexers = [
    {
      name = "1337x";
      definitionFile = "1337x";
      priority = 25;
      fields = {
        baseUrl = "https://1337x.to/";
        "baseSettings.limitsUnit" = 0;
        "torrentBaseSettings.preferMagnetUrl" = false;
        primarydownloadlink = 1;
        fallbackdownloadlink = 0;
        disablesort = false;
        sort = 2;
        type = 1;
      };
    }
    {
      name = "Nyaa.si";
      definitionFile = "nyaasi";
      # First priority on purpose: this is the indexer the anime libraries
      # actually rely on.
      priority = 1;
      fields = {
        "baseSettings.limitsUnit" = 0;
        "torrentBaseSettings.preferMagnetUrl" = false;
        prefer_magnet_links = true;
        sonarr_compatibility = false;
        strip_s01 = false;
        radarr_compatibility = false;
        "filter-id" = 0;
        "cat-id" = 0;
        sort = 0;
        type = 1;
      };
    }
    {
      name = "LimeTorrents";
      definitionFile = "limetorrents";
      priority = 50;
      fields = {
        "baseSettings.limitsUnit" = 0;
        "torrentBaseSettings.preferMagnetUrl" = false;
        primarydownloadlink = 1;
        fallbackdownloadlink = 0;
        sort = 2;
      };
    }
    {
      name = "The Pirate Bay";
      definitionFile = "thepiratebay";
      priority = 50;
      fields = {
        "baseSettings.limitsUnit" = 0;
        "torrentBaseSettings.preferMagnetUrl" = false;
        apiurl = "apibay.org";
        top100 = 6;
      };
    }
  ];

  syncConfig = pkgs.writeText "servarr-sync.json" (builtins.toJSON {
    inherit apps prowlarr indexers;

    # SeerrNG's own API key and its service links live in one root-only file.
    # These are the services that exist in the stack; a link left over from a
    # removed application is not this module's to delete, so SeerrNG's own
    # settings page is where a stale one goes.
    seerr = {
      port = 5055;
      settings = "/var/lib/seerr/settings.json";
      services = ["sonarr" "radarr" "lidarr"];
    };
    transmission = {
      # Transmission's RPC lives inside the WireGuard namespace, not on the
      # host: locally generated traffic never traverses PREROUTING, so the
      # namespace's veth peer is the address that works (the same reason the
      # Caddy vhost in jellyfin.nix uses it).
      host = config.vpnNamespaces.wg0.namespaceAddress;
      port = 9091;
      # The *arr apps talk to Transmission's RPC endpoint at /transmission/rpc.
      urlBase = "/transmission/";
    };
    flaresolverr_host = "http://127.0.0.1:8191";
    # Wait only long enough to cover a cold boot, where the *arr apps write
    # their config.xml (and therefore their API key) a few seconds after start.
    # This used to be 300 seconds, which was a mistake in both directions: it
    # turned one misdetected application into a five-minute stall, and because
    # this unit is pulled in by multi-user.target that stall held up
    # `nixos-rebuild switch` itself. The daily timer converges anything missed.
    wait_seconds = 60;
  });

  syncScript = pkgs.writers.writePython3Bin "servarr-sync" {
    # Long descriptive lines read better than wrapped ones here.
    flakeIgnore = ["E501"];
  } (builtins.readFile ./servarr-sync.py);

  appUnits = map (name: "${name}.service") (lib.attrNames apps);
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    systemd.services.servarr-sync = {
      description = "Converge Prowlarr indexers and applications, download clients, notifications";

      # Root, because the per-application state directories are 0700 and hold
      # the config.xml the API keys are read from.
      #
      # Type="exec", NOT the usual Type="oneshot" for a job like this. A
      # oneshot is "started" only once it exits, and this unit is pulled in by
      # multi-user.target - so `nixos-rebuild switch` would sit and wait for the
      # whole convergence run (and for its readiness polling) before finishing.
      # Convergence is not part of bringing the system up, so it must not be on
      # that path: systemd now considers the unit started as soon as the script
      # is exec'd, and a failure still marks it failed.
      serviceConfig = {
        Type = "exec";
        User = "root";
        Environment = "SERVARR_SYNC_CONFIG=${syncConfig}";
        # Same optional file the host health check uses: when it exists, its
        # ALERT_WEBHOOK_URL also becomes the *arr notification target, so
        # failures and health warnings reach the same place as everything else.
        # Without it, notifications are simply skipped.
        EnvironmentFile = "-/etc/nixos-alerts/webhook.env";
        ExecStart = lib.getExe syncScript;
      };

      wantedBy = ["multi-user.target"];
      wants = ["network-online.target" "prowlarr.service" "transmission.service"] ++ appUnits;
      after = ["network-online.target" "prowlarr.service" "transmission.service"] ++ appUnits;
    };

    # Also once a day, so a setting changed by hand in a web UI gets corrected
    # rather than quietly becoming the truth.
    systemd.timers.servarr-sync = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "05:00";
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
    };
  };
}
