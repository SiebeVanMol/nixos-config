# LVM cache and thin provisioning support for systems with LVM volumes.
{ config, lib, ... }: {
  config = lib.mkIf config.device.hardware.lvm.enable {
    boot.initrd.kernelModules = [
      "dm-cache-default"
    ];
    services.lvm.boot.thin.enable = true;
  };
}
