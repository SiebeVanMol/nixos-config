# Feral Gamemode: system optimisation daemon for gaming.
{
  config,
  lib,
  ...
}: {
  options.device.app.gamemode.enable =
    lib.mkEnableOption "Feral Gamemode, so games can request performance mode";

  config = lib.mkIf config.device.app.gamemode.enable {
    programs.gamemode.enable = true;
  };
}
