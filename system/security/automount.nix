# Automatic filesystem mounting: devmon, GVFS, and udisks2 for removable media.
{ config, lib, ... }: {
  config = lib.mkIf config.device.security.automount.enable {
    services.devmon.enable = true;
    services.gvfs.enable = true;
    services.udisks2.enable = true;
  };
}
