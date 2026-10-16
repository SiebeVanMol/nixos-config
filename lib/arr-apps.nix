# What this stack knows about each *arr application, in one place.
#
# The port, the dashboard row and - for the three that own a library - how to
# address that library were written in five places at once: the module that
# declares the service, the Python that sweeps or re-encodes the library, the
# Python that reports health, and the shell that collects widget keys. Adding an
# application, or moving one's port, meant finding every copy, and the copies had
# already drifted.
#
# A plain function, not a module, because the flake's own commands need it too:
# they run outside any host's configuration and have nothing else to read.
{lib}: rec {
  # "sonarr" -> "Sonarr": the name the *arr APIs, their project directories and
  # their dashboard tiles use.
  capitalize = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (lib.stringLength s) s;

  # Every application keeps its state - and, one level inside .config, the 0700
  # config.xml holding its API key - under its own name.
  dirOf = name: "/var/lib/${name}";

  # `items`, `rescan` and `idsKey` describe how to make the application look at
  # its library again, which only the scripts that re-encode or re-search need.
  # Prowlarr owns no library, so it carries the port alone.
  apps = {
    sonarr = {
      port = 8989;
      order = 10;
      description = "TV";
      category = "tv-sonarr";
      # Sonarr still calls its project NzbDrone, so that is the directory it
      # nests config.xml under.
      projectDir = "NzbDrone";
      items = "/series";
      rescan = "RescanSeries";
      idsKey = "seriesIds";
    };
    radarr = {
      port = 7878;
      order = 20;
      description = "Movies";
      category = "radarr";
      items = "/movie";
      rescan = "RescanMovie";
      idsKey = "movieIds";
    };
    lidarr = {
      port = 8686;
      order = 30;
      description = "Music";
      category = "lidarr";
      items = "/artist";
      rescan = "RescanArtist";
      idsKey = "artistIds";
    };
    prowlarr = {
      port = 9696;
    };
  };

  # The applications that own a library, which is the set the sweeping and
  # re-encoding scripts work on (Prowlarr only holds indexers).
  libraryApps = lib.filterAttrs (_: app: app ? items) apps;

  # What media.mkArr takes: the facts above minus the library extras it has no
  # use for, so a module for one application names only what is its own.
  mkArrArgs = name: {inherit name;} // lib.removeAttrs apps.${name} ["items" "rescan" "idsKey"];

  # The endpoint and library addressing of those applications, for the scripts
  # that cannot see a host's configuration (the flake commands) and so fall back
  # to these defaults. Deliberately no API version: the scripts probe /v3 and
  # /v1 at run time, because that literal went stale the last time Sonarr
  # changed major version and a stale one reads as "the application is broken".
  scripts = {
    apps =
      lib.mapAttrs (name: app: {
        inherit (app) port;
        dir = dirOf name;
        inherit (app) items rescan;
        path_key = "path";
        ids_key = app.idsKey;
      })
      libraryApps;
  };

  scriptsJSON = builtins.toJSON scripts;

  # The same shape, but read from a host's live registry: the port is an option,
  # so a host that moved one must not be reported on at the old number.
  withPorts = services: {
    apps = lib.mapAttrs (name: _: {
      port = services.${name}.port;
      dir = dirOf name;
    }) (lib.filterAttrs (name: _: builtins.hasAttr name apps) services);
  };
}
