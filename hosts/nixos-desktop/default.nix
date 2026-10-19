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
      jellyfin.enable = true;
      music.enable = true;
      # The local agent models: this host has the GPU for it, the others do not.
      #
      # Off for a day at the owner's request, because any request woke a model
      # and held its weights on the card for the whole fifteen-minute idle
      # window (`sleep-idle-seconds` in features/hermes/system.nix) - VRAM this machine
      # wants back while it is being used for something else. Back on with that
      # window cut to five minutes, which is the compromise the same complaint
      # asks for: a model still sleeps, it just stops costing the card ten
      # minutes earlier. Everything else stayed declared while it was off, and
      # features/hermes/home.nix gates its llamacpp endpoint, model aliases,
      # local cron default and the local aux slots on this one flag.
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
