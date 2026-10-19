# ZSA keyboard (Moonlander/Voyager) support and the Keymapp configuration tool.
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.device.hardware.zsa.enable =
    lib.mkEnableOption "ZSA keyboards and the Keymapp tool";

  config = lib.mkIf config.device.hardware.zsa.enable {
    hardware.keyboard.zsa.enable = true;
    environment.systemPackages = with pkgs; [keymapp];
  };
}
