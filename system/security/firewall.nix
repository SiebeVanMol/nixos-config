# Enable NixOS firewall.
{
  config,
  lib,
  ...
}: {
  options.device.security.firewall.enable =
    lib.mkEnableOption "the NixOS firewall";

  config = lib.mkIf config.device.security.firewall.enable {
    networking.firewall.enable = true;
  };
}
