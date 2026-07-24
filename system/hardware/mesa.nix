{ config, lib, pkgs, ... }: {
  config = lib.mkIf config.device.hardware.mesa.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        libva
        libva-vdpau-driver
        libvdpau-va-gl
        rocmPackages.clr.icd
      ];
    };
  };
}
