# Tailscale VPN mesh networking.
{
  config,
  lib,
  ...
}: {
  options.device.security.tailscale.enable =
    lib.mkEnableOption "Tailscale mesh networking";

  config = lib.mkIf config.device.security.tailscale.enable {
    services.tailscale.enable = true;
  };
}
