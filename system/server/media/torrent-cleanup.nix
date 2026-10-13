# Torrent cleanup: remove downloads that have stalled for good, and ask the
# application that wanted them to search again.
#
# Transmission never gives up and the *arr apps do not treat "stalled with no
# peers" as failure, so a dead torrent sits in .incomplete forever. Runs as root
# only because the API keys live in each app's root-only config.xml. The logic is
# in torrent-cleanup.py.
{
  config,
  lib,
  pkgs,
  ...
}: let
  script = pkgs.writers.writePython3Bin "torrent-cleanup" {
    # Long descriptive lines read better than wrapped ones here.
    flakeIgnore = ["E501"];
  } (builtins.readFile ./torrent-cleanup.py);

  # Derived from the registry, so the cleanup knows each application's port,
  # state directory, implementation and Transmission category without a second
  # list to keep in step.
  servarrApps = lib.mapAttrs (_: s: {
    inherit (s) port;
    inherit (s.servarr) category dir implementation;
  }) (lib.filterAttrs (_: s: s.servarr != null) config.device.media.services);

  cleanupConfig = pkgs.writeText "torrent-cleanup.json" (builtins.toJSON {
    transmission.url = "http://${config.vpnNamespaces.wg0.namespaceAddress}:${toString config.device.media.services.transmission.port}/transmission/rpc";
    stalled_days = config.device.media.stalledTorrentDays;
    apps = servarrApps;
  });
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    systemd.services.torrent-cleanup = {
      description = "Remove long-stalled torrents and ask the *arr apps to search again";
      after = ["transmission.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Environment = "TORRENT_CLEANUP_CONFIG=${cleanupConfig}";
        ExecStart = "${script}/bin/torrent-cleanup";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    systemd.timers.torrent-cleanup = {
      wantedBy = ["timers.target"];
      timerConfig = {
        # Daily is plenty: a torrent has to be stalled for days before it is a
        # candidate, so there is nothing to gain from checking more often.
        OnCalendar = "daily";
        RandomizedDelaySec = "20m";
        Persistent = true;
      };
    };
  };
}
