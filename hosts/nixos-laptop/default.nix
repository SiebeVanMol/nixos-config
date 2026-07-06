{ ... }: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix
    
    ../../system/wm/hyprland.nix

    ../../system/app/steam.nix
    ../../system/app/gamemode.nix
    ../../system/app/jellyfin.nix
    ../../system/app/kanata.nix

    ../../system/hardware/bluetooth.nix
    ../../system/hardware/backlight.nix

    ../../system/hardware/kernel.nix
    ../../system/hardware/time.nix
    
    ../../system/hardware/mesa.nix
    ../../system/hardware/nvidia.nix
    ../../system/hardware/zsa.nix

    ../../system/security/firewall.nix
    ../../system/security/tailscale.nix
    ../../system/security/automount.nix
    # ../../system/security/proton-vpn.nix
  ];

  # Bootloader.
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Enable networking
  networking.networkmanager.enable = true;
  networking.hostName = "nixos-laptop";

  services.power-profiles-daemon.enable = true;
  # Do not sleep if external display is connected.
  services.logind.settings.Login = {
    HandleLidSwitch = "poweroff";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

  # hardware.nvidia.prime = {
  #   offload.enable = true;
  #   nvidiaBusId = "PCI:1:0:0";
  #   intelBusId = "PCI:35:0:0";
  # };

  # Set your time zone.
  time.timeZone = "Europe/Brussels";

  system.stateVersion = "25.05";
}
