# Backlight control via Brillo and DDC/CI for external monitor brightness.
{ config, lib, username, ... }: {
  config = lib.mkIf config.device.hardware.backlight.enable {
    hardware.brillo.enable = true;
    boot = {
      extraModulePackages = with config.boot.kernelPackages; [ddcci-driver];
      kernelModules = [ "i2c-dev" "ddcci_backlight" ];
    };

    # Let the user control external monitors over DDC/CI (used by caelestia's
    # brightness slider via ddcutil). The i2c devices are root-only by default.
    services.udev.extraRules = ''
      KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
    '';
    users.groups.i2c = { };
    users.users.${username}.extraGroups = [ "i2c" ];
  };
}
