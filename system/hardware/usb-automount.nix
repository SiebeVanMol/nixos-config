# System-wide USB / removable storage automount via udev + systemd-mount.
#
# Unlike the session-based devmon/GVFS/udisks2 stack, this mounts straight from
# udev, so it works with no logged-in session (headless, SSH-only, GDM-less).
#
# Robustness comes from delegating the mount to systemd-mount rather than a
# hand-rolled helper: it schedules a real transient .mount/.automount unit
# (pulling in parent mounts and fsck), and in single-argument removable mode
# mounts under /run/media/system/<label> with the automount bound to the device's
# lifetime and a 1s idle timeout - so unplugging cleans it up with no registry or
# separate remove rule. FAT-family filesystems get uid/gid options so the
# logged-in desktop user can write them.
#
# On plug-in a notification goes to every logged-in session bus (caelestia
# provides org.freedesktop.Notifications); headless sessions get none. Neither
# behaviour hard-codes an owner - the scripts discover logged-in users by
# scanning /run/user/<uid>/bus, through one shared helper so both agree on what
# counts as a session.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.device.hardware.usb-automount;

  # "Which logged-in users have a session bus", as `uid:gid` lines, for both
  # scripts below. They used to walk /run/user themselves, and only the mount
  # handled a bus socket whose uid is not in passwd - the notification would
  # happily target it. A socket alone is not a session: a stale /run/user entry
  # left by a crashed session has a socket and no passwd line, and passing that
  # bare uid to systemd-mount fails the mount rather than skipping it.
  sessionOwners = pkgs.writeShellScript "usb-automount-sessions.sh" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.glibc.bin}/bin:$PATH"

    for bus in /run/user/*/bus; do
      [ -S "$bus" ] || continue
      uid="''${bus#/run/user/}"
      uid="''${uid%/bus}"
      owner="$(${pkgs.glibc.bin}/bin/getent passwd "$uid" 2>/dev/null)" || continue
      printf '%s:%s\n' \
        "$(printf '%s' "$owner" | cut -d: -f3)" \
        "$(printf '%s' "$owner" | cut -d: -f4)"
    done
  '';

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
        first="$(${sessionOwners} | ${pkgs.coreutils}/bin/head -n 1)"
        if [ -n "$first" ]; then
          IFS=: read -r oid ogid <<< "$first"
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
    for owner in $(${sessionOwners}); do
      uid="''${owner%%:*}"

      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
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
  options.device.hardware.usb-automount.enable =
    lib.mkEnableOption "automounting USB storage straight from udev";

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
