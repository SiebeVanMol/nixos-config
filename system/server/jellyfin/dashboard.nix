# The dashboard: one page that answers "where is everything and is it healthy".
#
# The stack had grown to fourteen services on fourteen *.lan names, which is the
# real source of the management overhead - not the apps themselves. This is the
# single place to look. It is deliberately read-mostly: every widget talks to an
# app's API and displays it, and nothing here can change your library. The one
# thing it *does* write is Homepage's own cache.
#
# Secrets: Homepage's widget configuration wants an API key per application, and
# its config lives in the world-readable Nix store. So the YAML below contains
# only {{HOMEPAGE_VAR_*}} placeholders, and homepage-env.sh reads the real keys
# out of each application's own configuration at runtime into a root-only
# environment file. Losing that file costs nothing but a warning in the journal;
# it is regenerated on every start of the unit.
#
# Which apps get a widget and which only a link is decided by one thing: whether
# the key is obtainable without a human. The *arr family, Bazarr and Seerr keep
# theirs in their own config files, so they get live widgets. Jellyfin and
# Kavita mint their API keys in their web UIs, so they stay links - create a key
# in each and they can be promoted to widgets later.
{
  config,
  lib,
  pkgs,
  ...
}: let
  booksEnabled = config.device.app.books.enable;

  envScript = pkgs.writeShellApplication {
    name = "homepage-env";
    runtimeInputs = [pkgs.coreutils pkgs.gnused pkgs.python3];
    text = builtins.readFile ./homepage-env.sh;
  };

  envFile = "/run/homepage-dashboard/env";

  # Loopback addresses, not the *.lan names: the dashboard runs on this host and
  # has no reason to go out through Caddy to reach its own services.
  widget = api: port: var: {
    widget = {
      type = api;
      url = "http://127.0.0.1:${toString port}";
      key = "{{${var}}}";
    };
  };

  arrServices = [
    {
      "Sonarr" =
        widget "sonarr" 8989 "HOMEPAGE_VAR_SONARR_KEY"
        // {
          href = "http://sonarr.lan";
          description = "TV";
        };
    }
    {
      "Radarr" =
        widget "radarr" 7878 "HOMEPAGE_VAR_RADARR_KEY"
        // {
          href = "http://radarr.lan";
          description = "Movies";
        };
    }
    {
      "Lidarr" =
        widget "lidarr" 8686 "HOMEPAGE_VAR_LIDARR_KEY"
        // {
          href = "http://lidarr.lan";
          description = "Music";
        };
    }
    {
      "Prowlarr" =
        widget "prowlarr" 9696 "HOMEPAGE_VAR_PROWLARR_KEY"
        // {
          href = "http://prowlarr.lan";
          description = "Indexers";
        };
    }
    {
      "Bazarr" =
        widget "bazarr" 6767 "HOMEPAGE_VAR_BAZARR_KEY"
        // {
          href = "http://bazarr.lan";
          description = "Subtitles";
        };
    }
  ];

  bookServices = [
    {
      "Readarr" =
        widget "readarr" 8787 "HOMEPAGE_VAR_READARR_KEY"
        // {
          href = "http://readarr.lan";
          description = "Ebooks";
        };
    }
  ];

  libraryServices = [
    {
      "Jellyfin" = {
        href = "http://jellyfin.lan";
        description = "Watch";
        icon = "jellyfin.png";
      };
    }
    {
      "Seerr" =
        widget "seerr" 5055 "HOMEPAGE_VAR_SEERR_KEY"
        // {
          href = "http://seerr.lan";
          description = "Requests";
        };
    }
    {
      "Kavita" = {
        href = "http://kavita.lan";
        description = "Read";
        icon = "kavita.png";
      };
    }
  ];

  downloadServices = [
    {
      # Transmission's RPC socket is inside the WireGuard namespace, so the
      # host's own loopback cannot reach it - the namespace address can, and
      # that is also what the *arr download clients use.
      "Transmission" = {
        href = "http://transmission.lan";
        description = "Torrents";
        widget = {
          type = "transmission";
          url = "http://${config.vpnNamespaces.wg0.namespaceAddress}:9091";
        };
      };
    }
  ];

  adminBookmarks =
    [
      {
        "FlareSolverr" = [
          {
            abbr = "FS";
            href = "http://flaresolverr.lan";
          }
        ];
      }
    ]
    ++ lib.optionals booksEnabled [
      {
        "Kapowarr" = [
          {
            abbr = "KP";
            href = "http://kapowarr.lan";
          }
        ];
      }
      {
        "Shelfmark" = [
          {
            abbr = "SM";
            href = "http://shelfmark.lan";
          }
        ];
      }
    ];
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = 8082;

      # Homepage refuses requests whose Host header it does not recognise, and
      # behind Caddy that header is the *.lan name rather than the port.
      allowedHosts = "home.lan,127.0.0.1:8082,localhost:8082";

      # The keys, read at runtime by homepage-env.service below.
      environmentFiles = [envFile];

      settings = {
        title = "Rat Nest";
        # Compact tiles: the point is to see status at a glance, not to scroll.
        layout = {
          Library = {
            style = "row";
            columns = 3;
          };
          Acquisition = {
            style = "row";
            columns = 5;
          };
          Downloads = {
            style = "row";
            columns = 2;
          };
        };
      };

      widgets = [
        {
          search = {
            provider = "duckduckgo";
            target = "_blank";
          };
        }
        {
          datetime = {
            text_size = "sm";
            format = {
              dateStyle = "medium";
              timeStyle = "short";
            };
          };
        }
      ];

      services = [
        {"Library" = libraryServices;}
        {"Acquisition" = arrServices ++ lib.optionals booksEnabled bookServices;}
        {"Downloads" = downloadServices;}
      ];

      bookmarks = [
        {"Tools" = adminBookmarks;}
      ];
    };

    # The unit fails outright when EnvironmentFile is missing, so this must run
    # first - and systemd's tmpfiles pre-creates the file for the case where the
    # script itself cannot (the dashboard then starts with widgets reporting
    # missing keys rather than not starting at all).
    systemd.tmpfiles.rules = [
      "d /run/homepage-dashboard 0700 root root -"
      "f /run/homepage-dashboard/env 0600 root root -"
    ];

    # systemd reads EnvironmentFile once, at start: a dashboard that is already
    # running never notices regenerated keys. Rather than have one unit restart
    # another (which deadlocks - see the note on homepage-env above), the unit
    # definition itself is made to depend on the collector: this variable holds
    # the collector's store path, so whenever that script changes, the
    # dashboard's unit changes with it and the switch restarts the dashboard
    # for us. That covers exactly the case that caused the stale Prowlarr key.
    systemd.services.homepage-dashboard.environment.HOMEPAGE_ENV_REV = "${envScript}";

    systemd.services.homepage-env = {
      description = "Collect API keys for the Homepage dashboard";
      before = ["homepage-dashboard.service"];
      wantedBy = ["homepage-dashboard.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStart = lib.getExe envScript;
        # A oneshot's default start timeout is INFINITE, so anything that hangs
        # in this unit hangs `nixos-rebuild switch` with it - which is precisely
        # how the deadlock above presented. The collector is a few file reads
        # and one write; if it cannot finish in a minute something is wrong, and
        # a bounded failure is far better than a rebuild that never returns.
        TimeoutStartSec = "60s";
      };

      # NOTE: this unit must never restart homepage-dashboard itself. That was
      # tried, and it deadlocks the whole switch: this unit is ordered Before
      # the dashboard, so the dashboard's start job waits for this unit to
      # finish, while an ExecStartPost here doing `systemctl try-restart
      # homepage-dashboard` waits for that very job. A oneshot has no start
      # timeout, so both hang until something external intervenes.
      #
      # Freshness is handled the other way round instead - see the
      # HOMEPAGE_ENV_REV environment variable on the dashboard below.
    };
  };
}
