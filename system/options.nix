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

  options.device.app = {
    steam = {
      enable = lib.mkEnableOption "Steam with Remote Play, Proton GE";
    };
    gamemode = {
      enable = lib.mkEnableOption "Feral Gamemode";
    };
    kanata = {
      enable = lib.mkEnableOption "Kanata keyboard remapper";
    };
    jellyfin = {
      enable = lib.mkEnableOption "Jellyfin media server";
    };
    minecraft = {
      enable = lib.mkEnableOption "Minecraft server";
    };
    virtualization = {
      enable = lib.mkEnableOption "QEMU/KVM + virt-manager";
    };
  };

  options.device.wm = {
    hyprland = {
      enable = lib.mkEnableOption "Hyprland compositor";
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
    reverse-proxy = {
      enable = lib.mkEnableOption "Caddy reverse proxy for LAN services";
      publicDomain = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Public domain served by the reverse proxy (e.g. snowyrenard.com). Empty = LAN-only.";
      };
    };
    ssh = {
      enable = lib.mkEnableOption "OpenSSH server";
    };
  };
}
