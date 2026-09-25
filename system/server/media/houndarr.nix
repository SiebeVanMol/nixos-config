# Houndarr: the search scheduler that keeps hunting for upgrades.
#
# The *arr applications only search when something asks them to: a new release,
# the RSS sync, or a human pressing "search". That is fine for new acquisitions,
# but it means a library full of H.264 files never notices that an HEVC or AV1
# release of the same film appeared years later - there is no new release to
# trigger on, only a better existing one.
#
# Houndarr closes that gap. On a schedule it asks each *arr application for its
# wanted/cutoff-unmet list and triggers a small, rate-limited batch of searches.
# The applications do the searching and the upgrade evaluation against the
# quality profile Recyclarr installed; Houndarr only decides when and how many,
# which is what keeps the indexers happy.
#
# It runs as an unprivileged user with no /Vault access at all - its whole
# world is its own SQLite state and four HTTP APIs.
#
# The one awkward part is the address. Houndarr's SSRF guard (see
# services/url_validation.py upstream) refuses to save an instance whose host is
# loopback, link-local or unspecified, and refuses `localhost` outright - it is
# written for a container talking to apps on the same Docker network, where
# `127.0.0.1` means "the container", never "the host". Private RFC1918 ranges,
# though, are explicitly allowed, because that is the normal self-hosted case.
#
# Every *arr app here listens on `*` and every `*.lan` name resolves to
# 127.0.0.1, so none of the obvious addresses can be entered. What the host does
# already have is a second, stable, private address: the media VPN bridge
# (see vpn.nix, and note it is gated on the same device.media.enabled expression
# that brings Houndarr up, so it is always present when Houndarr is). It is a
# local address, so traffic to it is routed over `lo` and never touches an
# interface or the firewall - it is purely a way to spell "this host" in a form
# the guard accepts.
#
# The `instanceHost` alias below gives that address a name (`media-host`), so
# the URL stored in Houndarr's database survives the address changing: it is
# derived from the namespace subnet, and the hosts entry is regenerated from the
# same value on every rebuild.
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

  # The search controls, declared once and written to every instance. The
  # numeric choices are reasoned about below rather than copied from the form
  # defaults, because "what is polite" depends on how big the library is.
  #
  # The sizing, measured on this host: 192 films, 39 series, 8 artists, and the
  # *arr applications' own wanted lists are small (6 films, 33 episodes, 1
  # album) because the RSS sync already chases new releases.
  tuning = {
    enabled = true;

    # Missing keeps Houndarr's defaults - this is the pass with the least left
    # to do - except for the hot-retry window. That exception matters: without
    # it, a missing item skipped for "the release is too new" waits the full
    # 14-day cooldown before it is looked for again, so an episode that aired
    # yesterday and had no release yet stays missing for a fortnight. With it,
    # the item is retried every six hours for the next two days.
    missing_enabled = true;
    batch_size = 2;
    sleep_interval_mins = 30;
    hourly_cap = 4;
    cooldown_days = 14;
    post_release_grace_hrs = 6;
    missing_hot_retry_window_hrs = 48;
    missing_hot_retry_interval_hrs = 6;

    # Stop searching while the application already has this many downloads
    # queued. Houndarr's default is 0, which disables the gate entirely: it will
    # happily search for 24 more things while 30 are still downloading and
    # importing. Five is high enough not to starve the pass and low enough to
    # hold it back when the queue is the actual bottleneck.
    queue_limit = 5;

    # Cutoff is the pass that matters here: it is the files whose existing copy
    # sits below the profile's cutoff, which with Recyclarr's profiles is the
    # H.264 library that has an HEVC or AV1 counterpart. 192 films and 39
    # series against a 21-day cooldown needs about 11 searches a day to keep
    # up, so Houndarr's single search an hour is already enough; two gives
    # headroom without leaving the cooldown as the only thing pacing indexers.
    cutoff_enabled = true;
    cutoff_batch_size = 2;
    cutoff_cooldown_days = 21;
    cutoff_hourly_cap = 2;

    # Upgrade is the library-wide hunt, walked a window of items at a time.
    # Deliberately left at Houndarr's pace: ~240 top-level items against a
    # 90-day cooldown needs about three searches a day, so one an hour is
    # already nine times more than the cooldown requires. Raising it would
    # spend indexer goodwill for nothing.
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

    # An episode/album is the precise and cheapest search. The alternative -
    # "season_context"/"artist_context" - widens a fruitless search to the
    # parent, which is how a batch release gets found; that is the knob to
    # reach for if anime season packs start being missed.
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
        # /var/lib/houndarr holds the SQLite database and the master key that
        # encrypts the API keys stored in it.
        #
        # The mode matters for more than the keys: the database also carries the
        # web password hash and the secret sessions are signed with, so a
        # world-readable one would let any local user mint an admin session.
        # UMask covers the files Houndarr creates itself (the database and its
        # WAL siblings), which systemd's directory mode cannot reach.
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

    # The state directory is created by systemd when the service starts, which
    # is after tmpfiles has already run, so an install predating
    # StateDirectoryMode keeps whatever mode it had. `d` adjusts the mode of an
    # existing directory as well as creating a missing one, which is what closes
    # that gap; everything inside it is then unreachable by path.
    systemd.tmpfiles.rules = ["d /var/lib/houndarr 0700 houndarr houndarr -"];

    # Houndarr has no configuration file and no environment variable for its
    # instances - they live in its SQLite database behind a session-authenticated
    # web UI - so this is the only way to make the setup reproducible rather than
    # a set of clicks that a rebuilt host would lose. See houndarr-config.py.
    systemd.services.houndarr-config = {
      description = "Converge Houndarr's instances and search settings from the media registry";

      # Ordered after the applications because it reads each one's API key out
      # of the config.xml that application writes for itself; the script polls
      # for the ones that are not there yet rather than assuming. Type="exec",
      # like servarr-sync, so a convergence run is never on the boot path that
      # `nixos-rebuild switch` waits for.
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
