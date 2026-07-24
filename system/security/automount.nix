{ config, lib, ... }: {
  config = lib.mkIf config.device.security.automount.enable {
    services.devmon.enable = true;
    services.gvfs.enable = true;
    services.udisks2.enable = true;
  };
}
