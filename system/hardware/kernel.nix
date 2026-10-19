# Latest Linux kernel, uinput module for input device emulation, low swappiness.
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.device.hardware.kernel.enable =
    lib.mkEnableOption "the latest kernel, uinput and low swappiness";

  config = lib.mkIf config.device.hardware.kernel.enable {
    boot = {
      kernelPackages = pkgs.linuxPackages_latest;
      consoleLogLevel = 0;
      kernel.sysctl = {
        "vm.swappiness" = 10;
      };
    };
    # `hardware.uinput.enable` supplies the kernel module, the `uinput` group and
    # the udev rule together, so none of the three is repeated here. Its rule is
    # the stricter one: it carries SUBSYSTEM=="misc", which a local copy of that
    # rule drops.
    hardware.uinput.enable = true;
  };
}
