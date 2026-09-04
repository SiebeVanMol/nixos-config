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
# FAT-family filesystems additionally get uid/gid mount options so the primary
# desktop user (`username`) can read and write them.
{
  config,
  lib,
  pkgs,
  username,
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
        if owner_line="$(${pkgs.glibc.bin}/bin/getent passwd "${username}" 2>/dev/null)"; then
          oid="$(printf '%s' "$owner_line" | cut -d: -f3)"
          ogid="$(printf '%s' "$owner_line" | cut -d: -f4)"
          opts="uid=$oid,gid=$ogid,fmask=0133,dmask=0022"
        fi
        ;;
    esac

    if [ -n "$opts" ]; then
      exec ${pkgs.systemd}/bin/systemd-mount --no-block --collect --options="$opts" "$DEVNAME"
    else
      exec ${pkgs.systemd}/bin/systemd-mount --no-block --collect "$DEVNAME"
    fi
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
    '';
  };
}
