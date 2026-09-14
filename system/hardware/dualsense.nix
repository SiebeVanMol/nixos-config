# Prevents DualSense touchpad from being picked up as a separate input device.
{
  pkgs,
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.device.hardware.dualsense.enable {
    hardware.uinput.enable = true;

    services.udev.packages = [pkgs.game-devices-udev-rules];
    services.udev.extraRules = ''
      ACTION=="add|change", ATTRS{name}=="*Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    '';
  };
}
