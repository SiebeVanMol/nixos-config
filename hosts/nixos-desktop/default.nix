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
      # The local agent model: this host has the GPU for it, the others do not.
      #
      # Off since 2026-10-17, at the owner's request: any request wakes a model
      # and holds its weights on the card for the whole fifteen-minute idle
      # window (`sleep-idle-seconds` in system/server/ai), which is VRAM this
      # machine wants back while it is being used for something else. Nothing
      # else had to change - the module, the models in /Vault and the endpoint
      # option all stay declared, and users/snowyrenard/hermes.nix gates its
      # llamacpp endpoint, model aliases, local cron default and the local aux
      # slots on this one flag, so a disabled host is left with nothing pointing
      # at a port that serves nothing. Re-enabling is this line and a switch;
      # the next session then loads a model again on first use, cold (~23 s for
      # the 12B, ~75 s for the 35B) unless /Vault's page cache still holds it.
      ai.enable = false;
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
