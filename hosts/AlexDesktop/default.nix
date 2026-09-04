# Alex's desktop configuration. DualSense controller, Asia/Tokyo timezone.
{...}: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix
  ];

  device = {
    hardware = {
      amd.enable = true;
      backlight.enable = true;
      dualsense.enable = true;
      kernel.enable = true;
      mesa.enable = true;
      time.enable = true;
      zsa.enable = true;
      usb-automount.enable = true;
    };
    security = {
      firewall.enable = true;
      tailscale.enable = true;
      proton-vpn.enable = true;
    };
    app = {
      steam.enable = true;
      gamemode.enable = true;
    };
    wm.hyprland.enable = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.networkmanager.enable = true;
  networking.hostName = "alex-desktop";

  time.timeZone = "Asia/Tokyo";

  system.stateVersion = "25.05";
}
