{ config, ... }: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix
    
    ../../system/wm/hyprland.nix

    ../../system/app/steam.nix
    ../../system/app/gamemode.nix
    ../../system/app/jellyfin.nix

    ../../system/hardware/kernel.nix
    ../../system/hardware/time.nix
    
    ../../system/hardware/amd.nix
    ../../system/hardware/mesa.nix
    ../../system/hardware/lvm.nix
    ../../system/hardware/bluetooth.nix
    ../../system/hardware/zsa.nix

    ../../system/security/firewall.nix
    ../../system/security/tailscale.nix
    ../../system/security/automount.nix
    ../../system/security/proton-vpn.nix
  ];

  # Bootloader.
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # External monitor brightness control for hypridle.
  boot.extraModulePackages = [config.boot.kernelPackages.ddcci-driver];
  boot.kernelModules = ["i2c-dev" "ddcci_backlight"];
  boot.kernelParams = [ "panic=10" ];

  # Enable networking
  networking.networkmanager.enable = true;
  networking.hostName = "nixos-desktop";

  # Set your time zone.
  time.timeZone = "Europe/Brussels";

  system.stateVersion = "25.05";
}
