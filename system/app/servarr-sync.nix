# Declarative settings sync for the Servarr stack (see servarr-sync.py).
#
# The rest of this directory declares which services run; this module converges
# the settings inside them, which until now were a manual checklist. The
# clearest example is the note on services.readarr in jellyfin.nix:
#
#   "In Readarr set: download client = Transmission (via the wg0 namespace
#    address, as in the `sites` entry above), indexers = Prowlarr, and root
#    folder = /Vault/Jellyfin/Books/Books."
#
# That is three web-UI sessions, replicated across four applications, that
# silently rot when a container path, port or key changes. Here it is a oneshot
# that runs after the services come up and every morning afterwards.
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
  #
  # Readarr is added only when the ebook/comic chain is enabled: a parked
  # service that never answers would otherwise make this unit log a warning on
  # every single run.
  apps =
    {
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
    }
    // lib.optionalAttrs config.device.app.books.enable {
      readarr = {
        port = 8787;
        dir = "/var/lib/readarr";
        implementation = "Readarr";
        category = "readarr";
      };
    };

  prowlarr = {
    port = 9696;
    dir = "/var/lib/prowlarr";
  };

  syncConfig = pkgs.writeText "servarr-sync.json" (builtins.toJSON {
    inherit apps prowlarr;
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
    # Checked, never created: a root folder needs quality and metadata profile
    # ids that this module does not own, so it only reports a missing one. Null
    # (not mkIf) because this whole attrset is serialised with toJSON, and only
    # relevant while the ebook/comic chain is enabled - the script treats null
    # as "skip this check".
    readarr_root_folder =
      if config.device.app.books.enable
      then "/Vault/Jellyfin/Books/Books"
      else null;
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
      description = "Converge Prowlarr applications, download clients and indexer proxies";

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
