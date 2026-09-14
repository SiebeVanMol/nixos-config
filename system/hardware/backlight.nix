# Backlight control via Brillo and DDC/CI for external monitor brightness.
{
  config,
  lib,
  usernames,
  pkgs,
  ...
}: {
  config = lib.mkIf config.device.hardware.backlight.enable {
    boot = {
      kernelModules = ["i2c-dev"];
    };

    environment.systemPackages = [pkgs.ddcutil];
    # Let users control external monitors over DDC/CI (used by caelestia's
    # brightness slider via ddcutil). The i2c devices are root-only by default.
    services.udev.extraRules = ''
      KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
    '';
    users.groups.i2c = {};
    # Grant DDC/CI access to every user on the host.
    users.users = lib.genAttrs usernames (_: {extraGroups = ["i2c"];});
  };
}
