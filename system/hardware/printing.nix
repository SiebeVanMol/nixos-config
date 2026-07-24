{ config, lib, ... }: {
  config = lib.mkIf config.device.hardware.printing.enable {
    services.printing.enable = true;
  };
}
