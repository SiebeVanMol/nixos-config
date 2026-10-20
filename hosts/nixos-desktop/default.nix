# Desktop machine configuration. Full workstation: Jellyfin media server, Minecraft server.
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
      lvm.enable = true;
      mesa.enable = true;
      time.enable = true;
      zsa.enable = true;
      dualsense.enable = true;
      usb-automount.enable = true;
    };
    security = {
      firewall.enable = true;
      tailscale.enable = true;
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
      workout.enable = true;
      jellyfin.enable = true;
      music.enable = true;
      # The local effort judge: Kev-0.8B on the CPU, 812 MB of RAM and no VRAM,
      # so it can stay on while the card goes to games. The agent itself runs on
      # DeepSeek; features/hermes/home.nix switches the effort plugin off on a
      # host without this flag, since there would be nobody to ask.
      ai.enable = true;
      minecraft.enable = false;
      virtualization.enable = true;
    };
    wm.hyprland.enable = true;
  };

  networking.hostName = "nixos-desktop";

  powerManagement.cpuFreqGovernor = "performance";

  # Nix builds get their own private, capped tmpfs. systemd creates it when the
  # daemon starts, tears it down with the daemon, and the rest of the system
  # never sees it. Build scratch is the one genuinely unbounded /tmp consumer on
  # this machine, so this keeps it out of the btrfs pool that /home shares with
  # /nix, and turns a runaway build into a failed build (ENOSPC) rather than an
  # OOM kill - there is no swap here. 16 GiB against 62 GiB of RAM; raise it if
  # a large build hits ENOSPC.
  systemd.services.nix-daemon.serviceConfig.TemporaryFileSystem = ["/tmp:size=16G,mode=1777"];

  time.timeZone = "Europe/Brussels";
}
