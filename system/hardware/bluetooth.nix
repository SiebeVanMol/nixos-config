{ config, lib, ... }: {
  config = lib.mkIf config.device.hardware.bluetooth.enable {
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;
  };
}
