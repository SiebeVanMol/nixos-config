# The media stack's service registry.
#
# Every service module in this directory (except the concern modules: proxy,
# dashboard, vpn, paths, options, default) registers itself here once, with
# everything the shared consumers need to know: the port the reverse proxy
# reaches it on, whether it is public, how it appears on the dashboard, whether
# it is a Servarr application, and what state belongs in the backup.
#
# The point is that adding a service touches ONE file. Before this, a new
# service meant editing layout.nix (the port table), dashboard.nix (the tiles),
# backup.nix (the state paths), proxy.nix and default.nix - five edits whose
# only guarantee was that you would forget one. Now the consumers below read
# the registry, so the single service file is the whole change.
#
# Registration is gated by each module's own `lib.mkIf`, so a disabled service
# simply does not exist here and no consumer has to know about it.
{
  config,
  lib,
  ...
}: let
  # A Homepage dashboard widget. `keyVar` names the HOMEPAGE_VAR_* placeholder
  # that dashboard.nix puts in the YAML; the real key is read at runtime by
  # homepage-env.sh, never stored here.
  widgetType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.str;
        description = "Homepage widget type, e.g. sonarr or transmission.";
      };
      keyVar = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "HOMEPAGE_VAR_* environment variable holding the API key, if the widget needs one.";
      };
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Override the widget API URL (default http://127.0.0.1:<port>, or the VPN namespace for a confined service).";
      };
    };
  };

  dashboardType = lib.types.submodule {
    options = {
      group = lib.mkOption {
        type = lib.types.enum [
          "library"
          "acquisition"
          "downloads"
          "admin"
        ];
        description = "Which row of the dashboard the service appears in; `admin` renders as a bookmark instead of a tile.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "One-word caption under the tile.";
      };
      title = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Display name on the dashboard; null uses the registry key.";
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Sort position within the dashboard group; lower comes first.";
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Homepage icon file name, e.g. jellyfin.png.";
      };
      href = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Link target (default http://<name>.lan), for a service whose browser address differs.";
      };
      abbr = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Two-letter abbreviation, for an `admin` bookmark.";
      };
      widget = lib.mkOption {
        type = lib.types.nullOr widgetType;
        default = null;
        description = "Live widget, or null for a plain link.";
      };
    };
  };

  # What servarr-sync.nix and the shared download directories need from a
  # *arr application. Registering it here is what lets those two stay generic.
  servarrType = lib.types.submodule {
    options = {
      implementation = lib.mkOption {
        type = lib.types.str;
        description = "API implementation name, e.g. Sonarr.";
      };
      dir = lib.mkOption {
        type = lib.types.str;
        description = "State/config directory, e.g. /var/lib/sonarr.";
      };
      category = lib.mkOption {
        type = lib.types.str;
        description = "Transmission category and /Vault/Downloads subdirectory, e.g. tv-sonarr.";
      };
    };
  };

  serviceType = lib.types.submodule {
    options = {
      port = lib.mkOption {
        type = lib.types.port;
        description = "Port the reverse proxy connects to.";
      };
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Upstream address; null means 127.0.0.1, a VPN-confined service sets the namespace veth address.";
      };
      public = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Also publish on <name>.<publicDomain>.";
      };
      dashboard = lib.mkOption {
        type = lib.types.nullOr dashboardType;
        default = null;
        description = "Dashboard entry, or null to keep the service off the dashboard (e.g. the dashboard itself).";
      };
      servarr = lib.mkOption {
        type = lib.types.nullOr servarrType;
        default = null;
        description = "Set for *arr applications; drives servarr-sync and the download directories.";
      };
      backup = {
        sqliteRoots = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Directories scanned for SQLite databases by the backup.";
        };
        statePaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Config/state files or directories copied verbatim by the backup.";
        };
      };
    };
  };
in {
  options.device.media = {
    # One computed switch for the shared plumbing (proxy, dashboard, VPN,
    # directories, backup): anything either stack needs exists when either
    # stack is on.
    enabled = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = config.device.app.jellyfin.enable || config.device.app.music.enable;
      description = "True when any media stack (Jellyfin or music) is enabled. Derived; do not set.";
    };

    services = lib.mkOption {
      type = lib.types.attrsOf serviceType;
      default = {};
      description = "Services in the media stack, each registered by its own module.";
    };

    stalledTorrentDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        Days a torrent may sit stalled with no activity before torrent-cleanup
        removes it and asks its *arr application to search for a replacement.
        Only torrents that are stalled *now* and have been idle this long are
        touched, so a merely slow download is left alone.
      '';
    };
  };
}
