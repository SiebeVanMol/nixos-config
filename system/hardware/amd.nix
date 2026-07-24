{ config, lib, pkgs, ... }: {
  config = lib.mkIf config.device.hardware.amd.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="powercap", ACTION=="add", RUN+="${pkgs.coreutils}/bin/chmod -R a+r /sys%p"
    '';
  };
}
