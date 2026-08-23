# Steam with Remote Play, LAN transfer, gamemode integration, and Proton GE.
{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.device.app.steam.enable {
    programs.steam = {
      enable = true;

      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;

      # Make gamemode available to every Steam title. Games can use it either
      # via the `gamemoderun %command%` launch option or through the daemon
      # enabled below (which is what makes it available by default).
      extraPackages = with pkgs; [gamemode];
      extraCompatPackages = with pkgs; [proton-ge-bin];
    };

    # Enable the Feral Gamemode daemon whenever Steam is enabled so games can
    # use gamemode out of the box.
    programs.gamemode.enable = true;
  };
}
