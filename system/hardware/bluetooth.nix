# Bluetooth hardware support. Bluez is required by the Caelestia shell's
# Bluetooth service; Blueman's GUI is no longer needed since the shell manages it.
{
  config,
  lib,
  ...
}: {
  options.device.hardware.bluetooth.enable =
    lib.mkEnableOption "Bluetooth, for the Caelestia shell's device panel";

  config = lib.mkIf config.device.hardware.bluetooth.enable {
    hardware.bluetooth.enable = true;
  };
}
