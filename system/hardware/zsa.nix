{ config, lib, pkgs, ... }: {
  config = lib.mkIf config.device.hardware.zsa.enable {
    hardware.keyboard.zsa.enable = true;
    environment.systemPackages = with pkgs; [ keymapp ];
  };
}
