# Feral Gamemode: system optimisation daemon for gaming.
{ config, lib, ... }: {
  config = lib.mkIf config.device.app.gamemode.enable {
    programs.gamemode.enable = true;
  };
}
