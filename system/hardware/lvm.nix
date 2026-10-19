# LVM cache and thin provisioning support for systems with LVM volumes.
# The NVMe writeback cache on Vault/lvol0 is attached in LVM metadata and
# re-activated automatically by LVM at boot; only the kernel module is needed.
{
  config,
  lib,
  ...
}: {
  options.device.hardware.lvm.enable =
    lib.mkEnableOption "LVM cache and thin provisioning";

  config = lib.mkIf config.device.hardware.lvm.enable {
    boot.initrd.kernelModules = [
      "dm-cache-default"
    ];
    boot.kernelModules = [
      "dm-cache-default"
    ];
    services.lvm.boot.thin.enable = true;
  };
}
