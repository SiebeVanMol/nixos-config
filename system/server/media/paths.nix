# The shared directories on /Vault, created once from the registry.
#
# Centralised for the same reason the registry exists: every path here was
# previously spelled out in whichever service happened to need it first, so
# adding a service meant remembering to add its directory too, and a missing
# setgid bit showed up much later as an EACCES three services down the chain.
#
# The per-application download directories are derived from the registry
# rather than listed: a *arr module says `category = "tv-sonarr"` and the
# directory appears, so a new application needs no edit here.
{
  config,
  lib,
  media,
  pkgs,
  ...
}: let
  servarrCategories = lib.unique (
    lib.mapAttrsToList (_: s: s.servarr.category) (
      lib.filterAttrs (_: s: s.servarr != null) config.device.media.services
    )
  );

  # The repair for everything tmpfiles cannot reach: the files INSIDE those
  # directories. See media-permissions.py for why they go wrong and why only
  # the group bits are touched.
  permissionRepair = pkgs.writers.writePython3Bin "media-permissions" {
    flakeIgnore = ["E501"];
  } (builtins.readFile ./media-permissions.py);
in {
  config = lib.mkIf config.device.media.enabled {
    # 2775 + setgid so files created inside keep the shared `users` group and
    # the next service in the chain can still write them.
    systemd.tmpfiles.rules =
      [
        "d ${media.downloads} 2775 root users -"
        "d ${media.downloads}/.incomplete 2775 root users -"
        "d ${media.mediaRoot} 2775 root users -"
        "d ${media.movies} 2775 root users -"
        "d ${media.shows} 2775 root users -"
        "d ${media.books} 2775 root users -"
        "d ${media.manga} 2775 root users -"
        "d ${media.musicLibrary} 2775 root users -"
        "d ${media.musicDownloads} 2775 root users -"
        "d ${media.musicIncomplete} 2775 root users -"
      ]
      ++ map (category: "d ${media.downloads}/${category} 2775 root users -") servarrCategories;

    # tmpfiles only ever sets the mode of the directories it creates. A file
    # written inside one keeps whatever group and mode the writing process had,
    # so a service that ran with a different primary group or a umask of 0077
    # leaves something the next service in the chain is refused access to - and
    # the refusal is reported as "Access to the path ... is denied", which reads
    # like a bug in the reader. This is the sweep that repairs those, so the
    # invariant is enforced rather than merely documented.
    systemd.services.media-permissions = {
      description = "Keep the media library readable and writable by the shared `users` group";
      # Also on every boot, not only on the timer's schedule: the walk is over
      # metadata and costs milliseconds, so making it part of coming up is
      # cheaper than wondering whether a repair has happened yet.
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = lib.getExe permissionRepair;
        # Metadata only, and the library is a few thousand files however many
        # TiB of media they hold; there is nothing here that needs to be fast.
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [media.mediaRoot];
      };
    };

    systemd.timers.media-permissions = {
      wantedBy = ["timers.target"];
      timerConfig = {
        # Daily, and at boot when the last run is older than that: Persistent
        # means a machine that was off overnight repairs itself on the way up.
        OnCalendar = "daily";
        RandomizedDelaySec = "5m";
        Persistent = true;
      };
    };
  };
}
