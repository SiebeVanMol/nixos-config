# NTP time synchronisation via systemd-timesyncd.
{
  config,
  lib,
  ...
}: {
  options.device.hardware.time.enable =
    lib.mkEnableOption "NTP time synchronisation";

  config = lib.mkIf config.device.hardware.time.enable {
    services.timesyncd.enable = true;
  };
}
