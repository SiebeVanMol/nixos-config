{ ... }: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix

    ../../system/wm/hyprland.nix

    ../../system/app/steam.nix
    ../../system/app/gamemode.nix
    ../../system/app/jellyfin.nix
    ../../system/app/minecraft.nix

    ../../system/security/firewall.nix
    ../../system/security/tailscale.nix
    ../../system/security/automount.nix
    ../../system/security/proton-vpn.nix
    ../../system/security/ssh.nix
  ];

  device.hardware = {
    amd.enable = true;
    backlight.enable = true;
    bluetooth.enable = true;
    kernel.enable = true;
    lvm.enable = true;
    mesa.enable = true;
    time.enable = true;
    zsa.enable = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.kernelParams = [ "panic=10" ];

  networking.networkmanager.enable = true;
  networking.hostName = "nixos-desktop";

  time.timeZone = "Europe/Brussels";

  system.stateVersion = "25.05";
}
