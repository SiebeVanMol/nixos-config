# ProtonVPN CLI and WireGuard tools.
{ config, lib, pkgs, ... }: {
  config = lib.mkIf config.device.security.proton-vpn.enable {
    environment.systemPackages = with pkgs; [wireguard-tools proton-vpn];
  };
}
