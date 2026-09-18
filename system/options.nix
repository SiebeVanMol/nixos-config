# Custom NixOS option declarations that act as feature toggles.
# Hosts enable subsets via device.hardware.<name>.enable and device.security.<name>.enable.
{
  lib,
  usernames,
  ...
}: {
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
    hipfire = {
      enable = lib.mkEnableOption "hipfire (ROCm) inference daemon as a per-user service";
      user = lib.mkOption {
        type = lib.types.str;
        default = lib.head usernames;
        description = "User whose session runs the hipfire daemon and owns its models.";
      };
      gpuTargets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["gfx1201"];
        description = ''
          AMD GPU architectures to compile hipfire kernels for. Must be
          non-empty when enabled; detect with:
            grep gfx_target_version /sys/class/kfd/kfd/topology/nodes/*/properties
        '';
      };
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
