# Custom NixOS option declarations that act as feature toggles.
# Hosts enable subsets via device.hardware.<name>.enable and device.security.<name>.enable.
{lib, ...}: {
  options.device.hardware = {
    amd = {
      enable = lib.mkEnableOption "AMD GPU powercap udev rules";
    };
    backlight = {
      enable = lib.mkEnableOption "backlight control (Brillo + DDC/CI)";
    };
    bluetooth = {
      enable = lib.mkEnableOption "Bluetooth (managed by the Caelestia shell)";
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
    usb-automount = {
      enable = lib.mkEnableOption "system-wide USB automount via udev + systemd-mount (no desktop session)";
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
    # The ebook/comic acquisition chain (Readarr/bookshelf, Kapowarr, Shelfmark).
    # Off by default: it is the most fragile part of the media stack - a
    # hand-built .NET 6 application pinned to two insecure packages, plus a
    # hand-written unit - and it had produced no files at all. Enable it when
    # the books and comics libraries are actually wanted; everything else in
    # the stack is unaffected either way.
    books = {
      enable = lib.mkEnableOption "ebook and comic acquisition (Readarr/bookshelf, Kapowarr, Shelfmark)";
    };
    ai = {
      enable = lib.mkEnableOption "llama.cpp (ROCm) server with Gemma 4 REAP 19B";
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
