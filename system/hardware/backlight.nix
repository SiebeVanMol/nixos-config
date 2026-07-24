# Backlight control via Brillo and DDC/CI for external monitor brightness.
{ config, lib, username, ... }: {
  config = lib.mkIf config.device.hardware.backlight.enable {
    hardware.brillo.enable = true;
    boot = {
      extraModulePackages = with config.boot.kernelPackages; [ddcci-driver];
      kernelModules = [ "i2c-dev" "ddcci_backlight" ];
    };
  };
}
