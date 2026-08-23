# Desktop machine configuration. Full workstation: Jellyfin media server, Minecraft server.
{...}: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix
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
      reverse-proxy = {
        enable = true;
        publicDomain = "snowyrenard.com";
      };
      ssh.enable = true;
    };
    app = {
      steam.enable = true;
      gamemode.enable = true;
      jellyfin.enable = true;
      dsh.enable = true;
      minecraft.enable = true;
      virtualization.enable = true;
    };
    wm.hyprland.enable = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.networkmanager.enable = true;
  networking.hostName = "nixos-desktop";

  powerManagement.cpuFreqGovernor = "performance";

  time.timeZone = "Europe/Brussels";

  system.stateVersion = "25.05";
}
