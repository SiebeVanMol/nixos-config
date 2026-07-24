{ config, lib, ... }: {
  config = lib.mkIf config.device.security.tailscale.enable {
    services.tailscale.enable = true;
  };
}
