# The mount points NixOS declares for btrfs filesystems, one per backing device.
#
# A single btrfs is routinely mounted several times: /home and /nix are
# subvolumes of one device on this host, and / and /var/tmp already share
# another. The maintenance modules that walk config.fileSystems want to check
# each underlying device once - capacity, per-device btrfs error counters and
# the weekly report would otherwise repeat every line per mount point. The
# scrub units are deduplicated by nixpkgs itself; this is for the checks those
# modules derive on their own.
{lib}: fileSystems: let
  btrfs = lib.filterAttrs (_: fs: (fs.fsType or "") == "btrfs") fileSystems;

  # Mount points are the attribute names, so `name` is the path to keep.
  addIfNewDevice = acc: name: let
    device = btrfs.${name}.device;
  in
    if lib.any (entry: entry.device == device) acc
    then acc
    else
      acc
      ++ [
        {
          inherit device;
          mountPoint = btrfs.${name}.mountPoint;
        }
      ];
in
  map (entry: entry.mountPoint) (lib.foldl' addIfNewDevice [] (lib.attrNames btrfs))
