# Steam with Remote Play, LAN transfer, gamemode integration, and Proton GE.
{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.device.app.steam.enable {
    programs.steam = {
      enable = true;

      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;

      extraPackages = with pkgs; [ gamemode ];
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
    };
  };
}
