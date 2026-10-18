# Periodic care for the disks: everything that can be reclaimed without deciding
# that some particular file is no longer wanted.
#
# Nothing here deletes media. What it removes regenerates or has no owner:
# journal entries beyond a size cap, Jellyfin's scratch transcodes, unfinished
# download fragments untouched for three months, crash dumps, and old system
# generations that only pin packages the store could otherwise free.
#
# Division of labour: this file does journald, caches, debris and the weekly
# report; monitoring.nix does smartd, btrfs scrub and capacity alerting;
# system/default.nix does weekly GC and SSD trim; backup.nix does restic.
#
# Deliberately NOT done: `btrfs balance` (no allocation slack to reclaim - 3.64
# TiB allocated against 3.56 TiB used, so it would move terabytes for nothing),
# and anything inside the media library, because deleting a film is a policy
# decision; the weekly report names the biggest items instead.
#
# systemd-tmpfiles-clean.timer already runs daily, so the age rules only name a
# directory and an age. Those rules are safe to leave running because systemd
# compares every timestamp a file has and removes it only when ALL are older than
# the age: a transfer still writing touches its ctime continuously, so a live
# download can never be swept.
{
  config,
  lib,
  media,
  pkgs,
  ...
}: let
  # Every /Vault path this module names comes from the shared layout in
  # lib/media.nix, which the flake hands to each module as `media`, so a library
  # move is one edit there rather than a hunt through the files mentioning it.
  inherit (media) downloads mediaRoot musicIncomplete vault;
  # The single media tree Jellyfin, Navidrome and Kavita all serve. It holds
  # the download staging directories too, so the report covers arrivals as
  # well as the library.
  library = mediaRoot;

  # Filesystems the report watches: every btrfs mount, since those hold data
  # rather than firmware. One entry per backing device, so /home and /nix - two
  # subvolumes of one device - do not produce two identical capacity lines.
  mounts = import ../../lib/btrfs-mounts.nix {inherit lib;} config.fileSystems;

  # Generations kept for rollback. Five gives days of "that update broke
  # something, boot the previous one" without pinning months of old packages.
  keepGenerations = 5;

  # The one webhook client, shared with monitoring.nix's daily health check.
  alertWebhook = import ../../lib/alert-webhook.nix {inherit pkgs;};

  pruneGenerations = pkgs.writeShellApplication {
    name = "prune-generations";
    runtimeInputs = [pkgs.nix];
    text = ''
      # Counted with a glob rather than `ls | grep`, which breaks on names that
      # are not plain alphanumerics - and these are symlinks named <n>-link.
      generation_count() {
        local count=0 profile
        for profile in /nix/var/nix/profiles/system-*-link; do
          [ -e "$profile" ] && count=$((count + 1))
        done
        printf '%s' "$count"
      }

      # Old system generations pin whole closures in the store, so the weekly GC
      # cannot free those packages while a generation still refers to them. Drop
      # all but the newest few and the next collection actually reclaims them.
      before="$(generation_count)"
      nix-env --profile /nix/var/nix/profiles/system \
        --delete-generations +${toString keepGenerations}
      after="$(generation_count)"
      echo "system generations: ''${before} before, ''${after} after (keeping ${toString keepGenerations})"
    '';
  };

  report = pkgs.writeShellApplication {
    name = "disk-care-report";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.systemd
      pkgs.util-linux
      pkgs.btrfs-progs
    ];
    text = ''
      findings=()

      # Capacity per filesystem, and the library's growth since the previous
      # run: the trend is what says whether last week's cleanup helped.
      state=/var/lib/disk-care-report/previous.txt
      mkdir -p "$(dirname "$state")"
      previous=""
      [ -r "$state" ] && previous="$(cat "$state")"

      while read -r mount; do
        [ -d "$mount" ] || continue
        pct="$(df --output=pcent "$mount" | tail -n 1 | tr -dc '0-9')"
        avail="$(df -h --output=avail "$mount" | tail -n 1 | tr -d ' ')"
        findings+=("$mount: ''${pct}% used, ''${avail} free")
      done <<< "${lib.concatStringsSep "\n" mounts}"

      library_mb="$(du -x -sm ${library} 2>/dev/null | awk '{print $1}')"
      if [ -n "$previous" ] && [ -n "$library_mb" ]; then
        delta=$(((library_mb - previous) / 1024))
        findings+=("library: ''${library_mb} MiB (''${delta} GiB since the previous report)")
      elif [ -n "$library_mb" ]; then
        findings+=("library: ''${library_mb} MiB (first report, nothing to compare yet)")
      fi

      # The biggest items, two levels deep, so the report names actual films and
      # series rather than just "Movies". This is the actionable half.
      findings+=("")
      findings+=("largest items under ${library}:")
      while IFS= read -r line; do
        findings+=("  $line")
        # $1 is the size and everything after it is the path: taking only $2
        # truncates every name at its first space, which turned "Shows/Doctor Who"
        # into "Shows/Doctor".
      done < <(du -x -m --max-depth=2 ${library} 2>/dev/null | sort -rn | head -12 \
        | awk '{size = $1; sub(/^[^[:space:]]+[[:space:]]+/, ""); printf "%7.1f GB  %s\n", size/1024, $0}')

      findings+=("")
      findings+=("journal: $(journalctl --disk-usage 2>/dev/null | tail -n 1); capped at 1G")
      findings+=("coredumps: $(du -sh /var/lib/systemd/coredump 2>/dev/null | cut -f1); older than a week are removed")
      generations=0
      for profile in /nix/var/nix/profiles/system-*-link; do
        [ -e "$profile" ] && generations=$((generations + 1))
      done
      findings+=("system generations: ''${generations}; all but the newest ${toString keepGenerations} are pruned monthly")
      # Every incomplete tree the tmpfiles rules below sweep has to be
      # counted here too - a tree named in one place and not the other is
      # how this figure came to exclude Soulseek's staging directory.
      fragmented="$(du -x -sm ${downloads}/.incomplete ${musicIncomplete} /var/lib/transmission/.incomplete 2>/dev/null | awk '{t+=$1} END {printf "%.1f", t/1024}')"
      findings+=("unfinished download fragments: ''${fragmented:-0} GB; those older than 90 days are removed")
      findings+=("$(btrfs filesystem usage ${vault} 2>/dev/null | grep -E 'Free \(estimated\)' | sed 's/^ *//')")

      report="$(printf '%s\n' "''${findings[@]}")"
      echo "=== disk care report ==="
      printf '%s\n' "$report"

      # Delivery is shared with the daily health check; lib/alert-webhook.nix
      # owns the truncation against Discord's cap and the "a failed webhook
      # is a warning, not a failed report" rule.
      printf '%s\n' "$report" \
        | ${lib.getExe alertWebhook} "$(hostname) weekly disk report"

      [ -n "$library_mb" ] && echo "$library_mb" > "$state"
    '';
  };
in {
  # The journal is the easiest real win here: 3 GiB of entries nobody reads. A
  # cap costs nothing because journald forgets the oldest first, and the per-file
  # limit keeps one noisy service from dominating the total.
  services.journald.settings.Journal = {
    SystemMaxUse = "1G";
    SystemMaxFileSize = "100M";
  };

  systemd.tmpfiles.rules = [
    # Jellyfin's transcoded fragments exist only while something is playing and
    # are rebuilt on demand, so anything older than a day is the residue of a
    # session that ended badly.
    "e /var/cache/jellyfin/transcodes 0700 jellyfin jellyfin 1d"
    # Unfinished download fragments, in both places they accumulate: the shared
    # download tree (25 GB at the time of writing) and Transmission's own home
    # (leftovers from before the incomplete directory moved onto /Vault). Three
    # months is long enough that no healthy transfer is still behind it; if
    # Transmission does still track one, its next check fails that torrent and
    # the *arr apps' removeFailedDownloads setting clears it away.
    "e ${downloads}/.incomplete - - - 90d"
    # Soulseek's incomplete tree, same reasoning and same age as the downloads
    # above: slskd is the other client that parks partial files on /Vault.
    "e ${musicIncomplete} - - - 90d"
    "e /var/lib/transmission/.incomplete - - - 90d"
    # Crash dumps are diagnostic debris, not records: a week is long enough to
    # notice one and read it, and pure disk otherwise.
    "e /var/lib/systemd/coredump - - - 7d"
  ];

  systemd.services.prune-generations = {
    description = "Drop old system generations so the store GC can reclaim them";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = lib.getExe pruneGenerations;
    };
  };

  systemd.timers.prune-generations = {
    wantedBy = ["timers.target"];
    timerConfig = {
      # Monthly, and timed ahead of the weekly store collection, so the packages
      # it frees are collected rather than waiting another week.
      OnCalendar = "monthly";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  systemd.services.disk-care-report = {
    description = "Weekly report on what is filling the disks";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      # A full scan of a 3.6 TiB library: be polite about it, and bound it so a
      # wedged filesystem cannot leave a stuck unit behind.
      Nice = 15;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "1h";
      EnvironmentFile = "-/etc/nixos-alerts/webhook.env";
      ExecStart = lib.getExe report;
    };
  };

  systemd.timers.disk-care-report = {
    wantedBy = ["timers.target"];
    timerConfig = {
      # Weekly, an hour before the restic backup, so the two never overlap.
      OnCalendar = "Sun 04:30";
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
  };
}
