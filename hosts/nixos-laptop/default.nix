{ ... }: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix

    ../../system/wm/hyprland.nix

    ../../system/app/steam.nix
    ../../system/app/gamemode.nix
    ../../system/app/kanata.nix

    ../../system/security/firewall.nix
    ../../system/security/tailscale.nix
    ../../system/security/automount.nix
    ../../system/security/proton-vpn.nix
  ];

  device.hardware = {
    amd.enable = true;
    backlight.enable = true;
    bluetooth.enable = true;
    kernel.enable = true;
    mesa.enable = true;
    nvidia.enable = true;
    time.enable = true;
    zsa.enable = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.networkmanager.enable = true;
  networking.hostName = "nixos-laptop";

  services.power-profiles-daemon.enable = true;
  services.logind.settings.Login = {
    HandleLidSwitch = "poweroff";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

  time.timeZone = "Europe/Brussels";

  system.stateVersion = "25.05";
}
