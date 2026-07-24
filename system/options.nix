{ lib, ... }: {
  options.device.hardware = {
    amd = {
      enable = lib.mkEnableOption "AMD GPU powercap udev rules";
    };
    backlight = {
      enable = lib.mkEnableOption "backlight control (Brillo + DDC/CI)";
    };
    bluetooth = {
      enable = lib.mkEnableOption "Bluetooth + Blueman";
    };
    dualsense = {
      enable = lib.mkEnableOption "DualSense controller touchpad ignore";
    };
    kernel = {
      enable = lib.mkEnableOption "latest kernel, uinput, swappiness";
    };
    lvm = {
      enable = lib.mkEnableOption "LVM cache support";
    };
    mesa = {
      enable = lib.mkEnableOption "Mesa graphics (enable + 32-bit)";
    };
    nvidia = {
      enable = lib.mkEnableOption "NVIDIA driver + VA-API";
    };
    time = {
      enable = lib.mkEnableOption "timesyncd";
    };
    zsa = {
      enable = lib.mkEnableOption "ZSA keyboard + keymapp";
    };
  };
}
