{ config, lib, pkgs, ... }: {
  config = lib.mkIf config.device.hardware.kernel.enable {
    boot = {
      kernelPackages = pkgs.linuxPackages_latest;
      extraModulePackages = [];
      kernelModules = [ "uinput" ];
      consoleLogLevel = 0;
      kernel.sysctl = {
        "vm.swappiness" = 10;
      };
    };
    hardware.uinput.enable = true;
    services.udev.extraRules = ''
      KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
    '';
    users.groups.uinput = {};
  };
}
