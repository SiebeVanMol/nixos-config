# Houndarr: the search scheduler that keeps hunting for upgrades.
#
# The *arr apps only search on a new release, the RSS sync, or a manual press, so
# a library full of H.264 never notices a later HEVC/AV1 release of the same
# film. On a schedule Houndarr reads each app's wanted/cutoff-unmet list and
# triggers a small, rate-limited batch of searches; the apps do the searching and
# evaluation, which keeps the indexers happy. It runs unprivileged with no /Vault
# access - only its SQLite state and four HTTP APIs.
#
# The awkward part is the address: Houndarr's SSRF guard rejects loopback,
# link-local, unspecified and `localhost`, but allows RFC1918. So it is given the
# media VPN bridge address (see vpn.nix, gated on the same device.media.enabled
# expression), reached over `lo`. The `instanceHost` alias names it `media-host`
# so the URL stored in Houndarr's database survives the address changing.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # The name Houndarr instances are entered with. Defined once here so the
  # hosts entry below and the documentation cannot drift apart; the header
  # explains why a name is needed at all.
  instanceHost = "media-host";

  # The host's second, non-loopback address: the media VPN bridge. See the
  # header for why this one and not the LAN address.
  instanceAddress = config.vpnNamespaces.wg0.bridgeAddress;

  # One Houndarr instance per *arr application, taken from the registry rather
  # than listed, so this file does not grow when another application joins the
  # stack (and a service that is off registers nothing to converge).
  apps = lib.mapAttrs (_: s: {
    host = instanceHost;
    inherit (s) port;
    inherit (s.servarr) dir implementation;
  }) (lib.filterAttrs (_: s: s.servarr != null) config.device.media.services);

  arrUnits = map (name: "${name}.service") (lib.attrNames apps);

  # The search controls, declared once and written to every instance. The numbers
  # below are reasoned about, not copied from the form defaults: "polite" depends
  # on library size (here 192 films, 39 series, 8 artists).
  tuning = {
    enabled = true;

    # Missing keeps the defaults except for the hot-retry window: without it a
    # "release too new" skip waits the full 14-day cooldown, so an episode that
    # aired yesterday with no release yet stays missing a fortnight.
    missing_enabled = true;
    batch_size = 2;
    sleep_interval_mins = 30;
    hourly_cap = 4;
    cooldown_days = 14;
    post_release_grace_hrs = 6;
    missing_hot_retry_window_hrs = 48;
    missing_hot_retry_interval_hrs = 6;

    # Stop searching while the application already has this many queued.
    # Houndarr's default 0 disables the gate entirely; five holds the pass back
    # only when the queue is the real bottleneck.
    queue_limit = 5;

    # Cutoff is the pass that matters: the files below the profile's cutoff, which
    # with Recyclarr's profiles is the H.264 library that has an HEVC/AV1
    # counterpart. 192 films and 39 series against a 21-day cooldown is ~11
    # searches a day, so two an hour has headroom without indexers bearing the
    # whole load.
    cutoff_enabled = true;
    cutoff_batch_size = 2;
    cutoff_cooldown_days = 21;
    cutoff_hourly_cap = 2;

    # Upgrade is the library-wide hunt, one item at a time. Left at Houndarr's
    # pace on purpose: ~240 items against a 90-day cooldown needs ~3 searches a
    # day, so one an hour is already nine times what the cooldown requires.
    upgrade_enabled = true;
    upgrade_batch_size = 1;
    upgrade_cooldown_days = 90;
    upgrade_hourly_cap = 1;
    upgrade_series_window_size = 5;

    # No time window: the caps above are the pacing, and a window would only
    # postpone a list this short. Random rather than chronological order, so a
    # pass does not walk the same head of the list every time.
    allowed_time_window = "";
    search_order = "random";

    # Tag filters would scope a pass to part of a library; nothing needs that.
    tag_filter_include = "";
    tag_filter_exclude = "";

    # An episode/album is the cheapest precise search. The alternative
    # ("season_context"/"artist_context") widens a fruitless search to the parent,
    # which is how a batch release gets found - reach for it if anime season packs
    # start being missed.
    search_modes = {
      sonarr = "episode";
      lidarr = "album";
    };
    upgrade_search_modes = {
      sonarr = "episode";
      lidarr = "album";
    };
  };

  configJson = pkgs.writeText "houndarr-config.json" (builtins.toJSON {
    data_dir = "/var/lib/houndarr";
    database = "/var/lib/houndarr/houndarr.db";
    # Long enough to cover a cold boot, where Houndarr is still creating its
    # schema and the *arr applications have not written config.xml yet.
    wait_seconds = 90;
    restart = true;
    inherit apps tuning;
  });

  # cryptography is all this needs beyond the standard library: it speaks to
  # Houndarr's database with sqlite3 and encrypts the API key with the same
  # Fernet primitive Houndarr uses.
  configScript = pkgs.writers.writePython3Bin "houndarr-config" {
    libraries = [pkgs.python3Packages.cryptography];
    flakeIgnore = ["E501"];
  } (builtins.readFile ./houndarr-config.py);
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # Makes `instanceHost` resolve to this host at a non-loopback address. The
    # *arr apps already listen on `*`, so nothing else is needed for Houndarr
    # to reach them at http://${instanceHost}:<port>.
    networking.hosts.${instanceAddress} = [instanceHost];

    users.groups.houndarr = {};
    users.users.houndarr = {
      isSystemUser = true;
      group = "houndarr";
      description = "Houndarr search scheduler";
    };

    systemd.services.houndarr = {
      description = "Houndarr: schedule *arr searches for missing and upgraded media";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "houndarr";
        Group = "houndarr";
        # /var/lib/houndarr holds the SQLite database, the master key for the
        # stored API keys, the web password hash and the session secret, so
        # StateDirectoryMode/UMask must stay 0700/0077.
        StateDirectory = "houndarr";
        StateDirectoryMode = "0700";
        UMask = "0077";
        ExecStart = "${lib.getExe pkgs.houndarr} --data-dir /var/lib/houndarr --host 127.0.0.1 --port ${toString 8877} --trusted-proxies 127.0.0.1";

        Restart = "on-failure";

        # No library access, no privileged operations: its whole world is its
        # own state directory and HTTP to the *arr APIs.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        CapabilityBoundingSet = "";
      };
    };

    # StateDirectory is created by systemd on first start, after tmpfiles has
    # run, so an install predating StateDirectoryMode keeps its old mode. `d`
    # fixes the mode of an existing directory too.
    systemd.tmpfiles.rules = ["d /var/lib/houndarr 0700 houndarr houndarr -"];

    # Houndarr has no config file or environment variable for its instances - they
    # live in its SQLite database behind a session-authenticated web UI - so this
    # is the only way to make the setup reproducible. See houndarr-config.py.
    systemd.services.houndarr-config = {
      description = "Converge Houndarr's instances and search settings from the media registry";

      # Ordered after the applications because it reads each one's API key out of
      # the config.xml that app writes for itself; the script polls for the ones
      # that are not there yet. Type="exec" so convergence is never on the boot
      # path `nixos-rebuild switch` waits for.
      after = ["houndarr.service"] ++ arrUnits;
      wants = ["houndarr.service"] ++ arrUnits;
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "exec";
        User = "root";
        Environment = "HOUNDARR_CONFIG=${configJson}";
        ExecStart = lib.getExe configScript;
      };
    };

    # Daily as well, so a setting changed in the web UI is corrected rather than
    # quietly becoming the truth.
    systemd.timers.houndarr-config = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "05:30";
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
    };

    device.media.services.houndarr = {
      port = 8877;
      dashboard = {
        group = "acquisition";
        order = 60;
        title = "Houndarr";
        description = "Upgrade hunt";
      };
      # The instance list (URLs + API keys, encrypted with houndarr.masterkey)
      # lives in the database, so both the database and the key have to come
      # back together or the keys are unreadable.
      backup = {
        sqliteRoots = ["/var/lib/houndarr"];
        statePaths = ["/var/lib/houndarr/houndarr.masterkey"];
      };
    };
  };
}
