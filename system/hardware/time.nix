{ config, lib, ... }: {
  config = lib.mkIf config.device.hardware.time.enable {
    services.timesyncd.enable = true;
  };
}
