# AMD GPU power management: grants read access to powercap sysfs for all users.
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.device.hardware.amd.enable =
    lib.mkEnableOption "AMD GPU power management, readable by every user";

  config = lib.mkIf config.device.hardware.amd.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="powercap", ACTION=="add", RUN+="${pkgs.coreutils}/bin/chmod -R a+r /sys%p"
    '';
  };
}
