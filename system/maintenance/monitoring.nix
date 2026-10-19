# Host-level health monitoring: SMART, btrfs scrub, and one daily pass that
# checks the things nobody notices until they bite.
#
# /Vault is a single 3.6 TiB disk holding the whole library and runs near-full,
# so the three failures worth catching early are a disk dying (SMART plus btrfs
# per-device error counters - data ratio is 1.00, so btrfs can DETECT bitrot but
# never repair it; backups are the only protection), a filesystem filling until
# imports fail with ENOSPC or it flips read-only, and a service that died days
# ago and took its dependants with it.
#
# The daily check logs to the journal and, if configured, to a webhook:
#   install -d -m 0755 /etc/nixos-alerts
#   printf 'ALERT_WEBHOOK_URL=%s\n' '...' > /etc/nixos-alerts/webhook.env
#   chmod 0600 /etc/nixos-alerts/webhook.env
# Optional; without it the check still logs and still fails its unit, which is
# what makes it visible in `systemctl --failed`. It excludes itself from that
# list so this does not cascade.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Every filesystem declared as btrfs is checked; that is where all the data
  # lives (/Vault, /home, /nix, /). FAT /boot is deliberately not watched, as
  # its constant high usage is normal and only adds noise. Each backing device
  # is checked once even when it is mounted at several points: /home and /nix
  # are subvolumes of the same 990 PRO, so capacity and `btrfs device stats`
  # would otherwise be reported twice.
  btrfsMounts = import ../../lib/btrfs-mounts.nix {inherit lib;} config.fileSystems;

  arrClient = import ../../lib/arr-client.nix {inherit pkgs;};
  arrApps = import ../../lib/arr-apps.nix {inherit lib;};

  # The one webhook client, shared with reclaim.nix's weekly report.
  alertWebhook = import ../../lib/alert-webhook.nix {inherit pkgs;};

  # Which applications the check reports on, from the live registry: the ports
  # are options, so the script must not carry its own copy of them. Baked into
  # the wrapper below rather than exported at the call site, because the call
  # site discards stderr and a missing file would then read as "all clear".
  arrHealthConfig = pkgs.writeText "arr-health.json" (
    builtins.toJSON (arrApps.withPorts config.device.media.services)
  );

  # Reports what the *arr services say about themselves; see the script.
  arrHealth = pkgs.writers.writePython3Bin "arr-health" {
    flakeIgnore = ["E501"];
    makeWrapperArgs = [
      "--set"
      "PYTHONPATH"
      "${arrClient}"
      "--set"
      "ARR_HEALTH_CONFIG"
      "${arrHealthConfig}"
    ];
  } (builtins.readFile ../server/media/arr-health.py);

  # Nushell, in a file: the script is mostly parsing, and a file is what
  # `checks.x86_64-linux.nu` can parse (a nushell string in this module cannot).
  # The substitutions are the script's dependencies, which nushell cannot declare
  # for itself: the tools it shells out to, the mounts to watch, and the two
  # binaries it calls.
  healthCheck = pkgs.writers.writeNuBin "nixos-health-check" {} (
    builtins.replaceStrings
    ["PATH_FROM_NIX" "MOUNTS_JSON" "ARR_HEALTH" "ALERT_WEBHOOK"]
    [
      (lib.makeBinPath [
        pkgs.systemd
        pkgs.coreutils
        pkgs.smartmontools
        pkgs.btrfs-progs
        pkgs.util-linux
      ])
      (builtins.toJSON btrfsMounts)
      (lib.getExe arrHealth)
      (lib.getExe alertWebhook)
    ]
    (builtins.readFile ./health-check.nu)
  );
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
  # report damage, but early reporting is the difference between restoring one
  # file from restic and discovering the loss later; metadata is DUP and is
  # genuinely repaired. The list is derived by nixpkgs from config.fileSystems,
  # which also asserts when autoScrub is on with nothing to scrub - what a host
  # with an ext4 root hits (alex-desktop).
  services.btrfs.autoScrub = lib.mkIf (btrfsMounts != []) {
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
