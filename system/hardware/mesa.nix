{ config, lib, ... }: {
  config = lib.mkIf config.device.hardware.mesa.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}
