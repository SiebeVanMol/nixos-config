# Enable NixOS firewall.
{ config, lib, ... }: {
  config = lib.mkIf config.device.security.firewall.enable {
    networking.firewall.enable = true;
  };
}
