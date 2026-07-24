# Desktop machine configuration. Full workstation: Jellyfin media server, Minecraft server.
{ ... }: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix

    ../../system/wm/hyprland.nix

    ../../system/app/steam.nix
    ../../system/app/gamemode.nix
    ../../system/app/jellyfin.nix
    ../../system/app/minecraft.nix

  ];

  device = {
    hardware = {
      amd.enable = true;
      backlight.enable = true;
      bluetooth.enable = true;
      kernel.enable = true;
      lvm.enable = true;
      mesa.enable = true;
      time.enable = true;
      zsa.enable = true;
    };
    security = {
      firewall.enable = true;
      tailscale.enable = true;
      automount.enable = true;
      proton-vpn.enable = true;
      ssh.enable = true;
    };
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.networkmanager.enable = true;
  networking.hostName = "nixos-desktop";

  time.timeZone = "Europe/Brussels";

  system.stateVersion = "25.05";
}
