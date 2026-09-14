# System-wide USB / removable storage automount via udev + systemd-mount.
#
# Unlike the session-based devmon/GVFS/udisks2 stack, this mounts USB storage
# straight from udev, so it works without any logged-in desktop session (headless,
# SSH-only, GDM-less machines).
#
# Robustness comes from delegating the actual mount to systemd-mount instead of
# running a hand-rolled `mount` helper:
#
#   * systemd-mount schedules the mount through the systemd job queue as a real
#     transient .mount/.automount unit (pulling in parent mounts / fsck), rather
#     than a raw mount(2) call in a shell script.
#   * In single-argument (removable-device) mode it probes the device and mounts
#     it under /run/media/system/<label>.
#   * Because the device is removable, systemd makes the automount *bound to the
#     backing device's lifetime* with a 1s idle timeout: it unmounts when idle
#     and is removed automatically when the device is unplugged — so there is no
#     manual lifecycle registry and no separate remove rule.
#
# FAT-family filesystems additionally get uid/gid mount options so whoever is
# logged into a desktop session can read and write them.
#
# On plug-in a desktop notification is also sent (via notify-send) to every
# logged-in desktop session — caelestia (Quickshell) provides the
# org.freedesktop.Notifications daemon. Headless/SSH sessions get no pop-up.
#
# Neither behaviour hard-codes a single owner: the scripts discover logged-in
# users at runtime by scanning their session buses under /run/user/<uid>/bus, so
# the module works on hosts with any number of users.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.device.hardware.usb-automount;

  # Runs from udev on a "block device with a filesystem appeared" event.
  # The udev properties DEVNAME / ID_FS_TYPE are exported into its environment.
  mountScript = pkgs.writeShellScript "usb-automount-mount.sh" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.glibc.bin}/bin:$PATH"

    # uid/gid/fmask/dmask are only valid on FAT-family filesystems; passing them
    # elsewhere makes the mount fail, so only add them for vfat/msdos/exfat.
    opts=""
    case "$ID_FS_TYPE" in
      vfat|msdos|exfat)
        # Own the FAT mount for the first logged-in desktop session we find.
        # /run/user/<uid>/bus exists only while a graphical session is active.
        for bus in /run/user/*/bus; do
          [ -S "$bus" ] || continue
          uid="''${bus#/run/user/}"
          uid="''${uid%/bus}"
          if owner_line="$(${pkgs.glibc.bin}/bin/getent passwd "$uid" 2>/dev/null)"; then
            oid="$(printf '%s' "$owner_line" | cut -d: -f3)"
            ogid="$(printf '%s' "$owner_line" | cut -d: -f4)"
            opts="uid=$oid,gid=$ogid,fmask=0133,dmask=0022"
            break
          fi
        done
        ;;
    esac

    if [ -n "$opts" ]; then
      exec ${pkgs.systemd}/bin/systemd-mount --no-block --collect --options="$opts" "$DEVNAME"
    else
      exec ${pkgs.systemd}/bin/systemd-mount --no-block --collect "$DEVNAME"
    fi
  '';

  # Best-effort desktop notification on plug-in. Runs as root from udev and sends
  # a pop-up through every logged-in user's session bus, silently doing nothing
  # for sessions without one (headless / SSH).
  notifyScript = pkgs.writeShellScript "usb-automount-notify.sh" ''
    set -u
    export PATH="${pkgs.coreutils}/bin:${pkgs.glibc.bin}/bin:$PATH"

    label="$ID_FS_LABEL"
    [ -n "$label" ] || label="$ID_FS_UUID"
    [ -n "$label" ] || label="USB storage device"

    # Notify each active graphical session. Cap each notify-send because it can
    # block waiting for an absent Notifications daemon, which we never want to
    # stall a udev worker.
    for bus in /run/user/*/bus; do
      [ -S "$bus" ] || continue
      uid="''${bus#/run/user/}"
      uid="''${uid%/bus}"

      export DBUS_SESSION_BUS_ADDRESS="unix:path=$bus"
      export XDG_RUNTIME_DIR="/run/user/$uid"
      export HOME="/run/user/$uid"

      ${pkgs.coreutils}/bin/timeout 5 \
        ${pkgs.libnotify}/bin/notify-send \
        -a "usb-automount" -i "drive-removable-media" \
        "Removable storage connected" "$label" >/dev/null 2>&1
    done
    exit 0
  '';
in {
  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      # Mount USB storage that carries a filesystem. ENV{ID_FS_USAGE}=="filesystem"
      # matches both partitioned drives (their partitions) and whole-disk
      # "superfloppy" sticks (the raw block device), while KERNEL=="sd*" +
      # ENV{ID_BUS}=="usb" keeps us on USB drives. systemd-mount's removable-mode
      # automount handles unmounting and unplug cleanup, so no ACTION=="remove"
      # rule is needed here.
      KERNEL=="sd*", SUBSYSTEM=="block", ACTION=="add", ENV{ID_BUS}=="usb", ENV{ID_FS_USAGE}=="filesystem", RUN+="${mountScript}"

      # Best-effort desktop notification of the new connection.
      KERNEL=="sd*", SUBSYSTEM=="block", ACTION=="add", ENV{ID_BUS}=="usb", ENV{ID_FS_USAGE}=="filesystem", RUN+="${notifyScript}"
    '';
  };
}
