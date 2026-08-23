# Prevents DualSense touchpad from being picked up as a separate input device.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.device.hardware.dualsense.enable {
    services.udev.extraRules = ''
      ACTION=="add|change", ATTRS{name}=="*Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    '';
  };
}
