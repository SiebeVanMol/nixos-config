# Declarative settings sync for the Servarr stack (see servarr-sync.py).
#
# Converges the settings that were a manual web-UI checklist: each app's download
# client, the apps Prowlarr pushes indexers to, the notification target, and
# SeerrNG's links. A oneshot after the services come up and every morning after.
#
# Two properties make it safe unattended: it reads API keys at runtime from each
# app's config.xml, so no secret enters the store; and every write is a
# create-or-converge, so a repeat run is a no-op. Indexers are deliberately NOT
# declared - their credentials are per-site personal secrets, so Prowlarr's own
# UI owns them.
{
  config,
  lib,
  pkgs,
  media,
  ...
}: let
  arrClient = import ../../../lib/arr-client.nix {inherit pkgs;};

  # Prowlarr is not built by mkArr (it owns no library), so its state directory
  # comes from the shared facts instead of being written out again here.
  arrApps = import ../../../lib/arr-apps.nix {inherit lib;};

  # Derived from the registry: each *arr service registers its implementation,
  # state directory and Transmission category, so this no longer duplicates
  # them (or the ports and download directories they imply).
  apps = lib.mapAttrs (_: s: {
    inherit (s) port;
    inherit (s.servarr) dir implementation category;
  }) (lib.filterAttrs (_: s: s.servarr != null) config.device.media.services);

  prowlarr = {
    port = config.device.media.services.prowlarr.port;
    dir = arrApps.dirOf "prowlarr";
  };

  # Where the library lived before the servers became peers of it rather than
  # tenants of Jellyfin's; see lib/media.nix. Every item each *arr manages still
  # records an absolute path under here.
  legacyRoot = "${media.vault}/Jellyfin";

  # Exactly what `nix run .#servarr-export` read back from the live instance, so
  # the first convergence is a no-op. The `info_*` fields are omitted on purpose:
  # Prowlarr fills in that help text itself. None of these four needs a
  # credential; a private tracker would add its login via the root-only secrets.
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

    # Require a login for every application's web UI, with the password from the
    # file the activation script below generates. Without this the UI answers a
    # LAN request with its API key (see sync_authentication in the script).
    authentication = {
      inherit (arrApps.uiAuth) username;
      password_file = arrApps.uiAuth.passwordFile;
    };

    # Each *arr needs a root folder. The default quality profile is NOT set here:
    # only Lidarr's root folders carry one, so the import list or the requesting
    # application owns that choice.
    root_folders = {
      sonarr = media.shows;
      radarr = media.movies;
      lidarr = media.musicLibrary;
    };

    # Moving the library updates the root folder above but NOT the absolute
    # directory each item stores of itself; the old -> new prefix declarations
    # below repair that (the apps report it as "access denied" imports).
    library_moves = {
      sonarr = [
        {
          from = "${legacyRoot}/Shows";
          to = media.shows;
        }
      ];
      radarr = [
        {
          from = "${legacyRoot}/Movies";
          to = media.movies;
        }
      ];
      lidarr = [
        {
          from = "${legacyRoot}/Music";
          to = media.musicLibrary;
        }
      ];
    };

    # SeerrNG's API key and service links live in one root-only file. A stale
    # link from a removed app is left to SeerrNG's own settings page.
    seerr = {
      port = config.device.media.services.seerr.port;
      settings = "/var/lib/seerr/settings.json";
      services = lib.attrNames apps;
      # Where "new requests are 1080p" is set: Sonarr/Radarr root folders carry
      # no default profile of their own. A service absent here keeps whatever its
      # link already uses.
      quality_profiles = {
        sonarr = "Remux + WEB 1080p";
        radarr = "Remux + WEB 1080p";
      };
    };
    transmission = {
      # Transmission's RPC is inside the WireGuard namespace, not on the host:
      # locally generated traffic skips PREROUTING, so the veth peer is the
      # address that works (same reason its Caddy vhost uses it).
      host = config.vpnNamespaces.wg0.namespaceAddress;
      port = config.device.media.services.transmission.port;
      # The *arr apps talk to Transmission's RPC endpoint at /transmission/rpc.
      urlBase = "/transmission/";
    };
    flaresolverr_host = "http://127.0.0.1:${toString config.device.media.services.flaresolverr.port}";
    # Long enough to cover a cold boot, where the *arr apps write config.xml (and
    # their key) a few seconds after start. The old 300s turned one misdetected
    # app into a five-minute stall that held up multi-user.target.
    wait_seconds = 60;
  });

  syncScript = pkgs.writers.writePython3Bin "servarr-sync" {
    # Long descriptive lines read better than wrapped ones here.
    flakeIgnore = ["E501"];
    makeWrapperArgs = ["--set" "PYTHONPATH" "${arrClient}"];
  } (builtins.readFile ./servarr-sync.py);

  appUnits = map (name: "${name}.service") (lib.attrNames apps);
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # The UI login every application in the stack is given. Generated once, the
    # way backup.nix generates the restic password, and deliberately not in the
    # store: a generated password in a world-readable path is no password, and
    # regenerating it on every switch would lock every browser out.
    system.activationScripts.servarr-ui-password.text = ''
      if [ ! -s ${arrApps.uiAuth.passwordFile} ]; then
        ${pkgs.coreutils}/bin/install -d -m 0700 $(dirname ${arrApps.uiAuth.passwordFile})
        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.coreutils}/bin/head -c 24 /dev/urandom | ${pkgs.coreutils}/bin/base64 --wrap=0 > "$tmp"
        ${pkgs.coreutils}/bin/install -m 0600 "$tmp" ${arrApps.uiAuth.passwordFile}
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
    '';

    systemd.services.servarr-sync = {
      description = "Converge Prowlarr indexers and applications, download clients, notifications";

      # Root, because the 0700 state directories hold the config.xml the keys are
      # read from.
      #
      # Type="exec", not "oneshot": this unit is pulled in by multi-user.target,
      # and a oneshot is only "started" once it exits, so the switch would block
      # on the whole convergence run. Convergence is not part of boot.
      serviceConfig = {
        Type = "exec";
        User = "root";
        Environment = "SERVARR_SYNC_CONFIG=${syncConfig}";
        # Same optional file the host health check uses: when present its
        # ALERT_WEBHOOK_URL also becomes the *arr notification target.
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
