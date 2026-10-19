# Laptop machine configuration. NVIDIA GPU, keyboard remapping, power management (lid switch).
{...}: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix
  ];

  device = {
    # The overlay pins in overlays/ are only watched where the checkout lives;
    # the weekly check posts what it finds to the alert webhook.
    maintenance.overlays = {
      enable = true;
    };
    hardware = {
      amd.enable = true;
      backlight.enable = true;
      bluetooth.enable = true;
      kernel.enable = true;
      mesa.enable = true;
      nvidia.enable = true;
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
      kanata.enable = true;
    };
    wm.hyprland.enable = true;
  };

  networking.hostName = "nixos-laptop";

  services.power-profiles-daemon.enable = true;
  services.logind.settings.Login = {
    HandleLidSwitch = "poweroff";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

  time.timeZone = "Europe/Brussels";
}
