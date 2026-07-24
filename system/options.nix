# Custom NixOS option declarations that act as feature toggles.
# Hosts enable subsets via device.hardware.<name>.enable and device.security.<name>.enable.
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

  options.device.security = {
    firewall = {
      enable = lib.mkEnableOption "Firewall";
    };
    tailscale = {
      enable = lib.mkEnableOption "Tailscale VPN";
    };
    automount = {
      enable = lib.mkEnableOption "Automatic mounting (devmon, gvfs, udisks2)";
    };
    proton-vpn = {
      enable = lib.mkEnableOption "ProtonVPN CLI tools";
    };
    ssh = {
      enable = lib.mkEnableOption "OpenSSH server";
    };
  };
}
