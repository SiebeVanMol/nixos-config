# Host-level health monitoring: SMART, btrfs scrub, and one daily pass that
# checks the things nobody notices until they bite.
#
# Nothing here existed before, which mattered because /Vault is a single 3.6 TiB
# disk holding the whole library and it has been running at 98% full. The three
# failure modes worth catching early:
#
#   * a disk quietly dying (SMART, and btrfs per-device error counters - note
#     that the vault's data ratio is 1.00, so btrfs can DETECT bitrot but can
#     never repair it; backups are the only real protection, see backup.nix),
#   * a filesystem filling up far enough that imports start failing with
#     ENOSPC or the filesystem flips read-only,
#   * a service that died days ago and took its dependants with it.
#
# The daily check reports to the journal and, if configured, to a webhook:
#
#   install -d -m 0755 /etc/nixos-alerts
#   printf 'ALERT_WEBHOOK_URL=%s\n' 'https://discord.com/api/webhooks/...' \
#     > /etc/nixos-alerts/webhook.env
#   chmod 0600 /etc/nixos-alerts/webhook.env
#
# The file is optional; without it the check still logs and still fails its
# unit, which is what makes problems visible in `systemctl --failed`. The check
# excludes itself from that list so this does not cascade.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Every filesystem declared as btrfs is checked; that is where all the data
  # lives (/Vault, /home, /nix, /). FAT /boot is deliberately not watched, as
  # its constant high usage is normal and only adds noise.
  btrfsMounts =
    lib.mapAttrsToList (mountPoint: _: mountPoint)
    (lib.filterAttrs (_: fs: (fs.fsType or "") == "btrfs") config.fileSystems);

  mountsArg = lib.concatStringsSep " " (map lib.escapeShellArg btrfsMounts);

  # Reports what the *arr services say about themselves; see the script.
  arrHealth = pkgs.writers.writePython3Bin "arr-health" {
    flakeIgnore = ["E501"];
  } (builtins.readFile ./server/jellyfin/arr-health.py);

  healthCheck = pkgs.writeShellApplication {
    name = "nixos-health-check";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.curl
      pkgs.jq
      pkgs.smartmontools
      pkgs.btrfs-progs
      pkgs.util-linux
      pkgs.systemd
    ];
    text = ''
            findings=()
            critical=0
            note() { findings+=("$1"); }
            # A critical finding is one where something is already broken or about
            # to be: the unit fails so it shows up in `systemctl --failed`.
            # Warnings are reported and sent to the webhook but leave the unit
            # green, because a check that turns red every day for something
            # merely worth knowing is a check nobody reads.
            note_critical() {
              note "$1"
              critical=1
            }

            # 1. Services that are not running. Dependants of a dead service usually
            #    fail too, so one root cause shows up as several lines here.
            failed="$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null \
              | awk '{print $1}' | grep -v '^nixos-health-check' || true)"
            if [ -n "$failed" ]; then
              note_critical "failed systemd units:"
              while IFS= read -r unit; do
                note "  $unit"
              done <<< "$failed"
            fi

            for mount in ${mountsArg}; do
              [ -d "$mount" ] || continue

              # 2. Capacity. 95% leaves no room for a large import; 90% is the point
              #    to start pruning.
              pct="$(df --output=pcent "$mount" 2>/dev/null | tail -n 1 | tr -dc '0-9' || true)"
              if [ -n "$pct" ]; then
                if [ "$pct" -ge 95 ]; then
                  note_critical "CRITICAL: $mount is ''${pct}% full"
                elif [ "$pct" -ge 90 ]; then
                  note "warning: $mount is ''${pct}% full"
                fi
              fi

              # 3. btrfs per-device error counters. A non-zero counter means the
              #    kernel already saw IO that it could not fix.
              errors="$(btrfs device stats "$mount" 2>/dev/null | awk '$NF != 0' || true)"
              if [ -n "$errors" ]; then
                note_critical "CRITICAL: btrfs device errors on $mount:"
                while IFS= read -r line; do
                  note "  $line"
                done <<< "$errors"
              fi
            done

            # 4. SMART overall health, one line per physical disk. Devices that do
            #    not report a health line (USB bridges, virtual disks) are skipped
            #    rather than reported as failures.
            for disk in $(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1}'); do
              health="$(smartctl -H "/dev/$disk" 2>/dev/null \
                | sed -n 's/.*self-assessment test result: *//p' | head -n 1 || true)"
              [ -n "$health" ] || continue
              case "$health" in
                PASSED | OK | PASSED*) : ;;
                *) note_critical "CRITICAL: SMART health on /dev/$disk: $health" ;;
              esac
            done

            # 5. The *arr services' own health warnings: an indexer that started
            #    refusing connections, a download client that went away, a root
            #    folder that is no longer writable. Each application already
            #    knows this and exposes it on /api/<v>/health; without this the
            #    only way to learn about it is to open four web UIs and look.
            #    Warnings, not critical: the stack still plays and still imports.
            arr_health="$(${lib.getExe arrHealth} 2>/dev/null || true)"
            if [ -n "$arr_health" ]; then
              while IFS= read -r line; do
                [ -n "$line" ] && note "$line"
              done <<< "$arr_health"
            fi

            if [ "''${#findings[@]}" -eq 0 ]; then
              echo "nixos health check: all clear"
              exit 0
            fi

            report="$(printf '%s\n' "''${findings[@]}")"
            echo "=== nixos health check: ''${#findings[@]} finding(s) ==="
            printf '%s\n' "$report"

            if [ -n "''${ALERT_WEBHOOK_URL:-}" ]; then
              # Discord caps message content at 2000 characters.
              payload="$(hostname): ''${#findings[@]} health finding(s)
      ''${report:0:1800}"
              if jq -n --arg content "$payload" '{content: $content}' \
                | curl -sfS -X POST -H 'Content-Type: application/json' \
                    --data-binary @- "$ALERT_WEBHOOK_URL" >/dev/null; then
                echo "(alert delivered)"
              else
                echo "WARNING: could not deliver the alert webhook" >&2
              fi
            else
              echo "(ALERT_WEBHOOK_URL unset; journal only)"
            fi

            # Only a critical finding fails the unit; warnings are reported and
            # delivered but leave `systemctl --failed` clean.
            [ "$critical" -eq 1 ] && exit 1
            exit 0
    '';
  };
in {
  # Real-time disk monitoring between the daily checks. Its own notifications
  # reach the journal and wall(1); anything it finds also shows up in the log
  # the daily check reports from.
  services.smartd = {
    enable = true;
    # Already the module default, stated for intent: a failing disk should
    # shout at whoever is logged in, not only write to the journal.
    notifications.wall.enable = true;
    # -a: all attributes, -o on / -S on: run the offline and self-test
    # schedules, -W 4,45,55: warn at 45 C, which is where the vault disk starts
    # to be worth looking at.
    defaults.monitored = "-a -o on -S on -W 4,45,55";
  };

  # Weekly scrub of every btrfs filesystem. On single-copy data this can only
  # report damage, but reporting it early is the difference between restoring
  # one file from restic and discovering the loss later. Metadata is DUP, so
  # that part is genuinely repaired.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
  };

  systemd.services.nixos-health-check = {
    description = "Daily host health check (failed units, capacity, btrfs, SMART)";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      EnvironmentFile = "-/etc/nixos-alerts/webhook.env";
      ExecStart = lib.getExe healthCheck;
    };
  };

  systemd.timers.nixos-health-check = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "09:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };
}
