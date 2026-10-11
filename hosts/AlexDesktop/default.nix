# Alex's desktop configuration. DualSense controller, Asia/Tokyo timezone and
# East Asian binary cache mirrors.
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

  # Binary caches. This machine is in Japan, and a rebuild from nothing spends
  # most of its time waiting on cache.nixos.org from there. The two below are
  # mirrors of that same cache that answer from East Asia, so they are listed
  # first. nixpkgs appends https://cache.nixos.org/ after whatever is listed
  # here (mkAfter, in nixos/modules/config/nix.nix), so the official cache is
  # still there as the fallback and does not need repeating.
  #
  # Nothing is being trusted that was not trusted before: a mirror serves the
  # same NARs with the same cache.nixos.org-1 signatures, `require-sigs` is
  # still on, and the signing key is unchanged, so tampered content is rejected
  # exactly as it would be from the official cache. This is per-host, so the
  # European machines are untouched.
  #
  # If one of these turns out to be slow from Tokyo, measure before reordering
  # rather than guessing - mirrors.ustc.edu.cn is the other one worth trying.
  # Any store path maps to <cache>/<basename>.narinfo:
  #   P=$(ls -d /nix/store/*-bash-interactive-* | head -1)
  #   curl -so /dev/null -w '%{speed_download} B/s\n' \
  #     "https://mirror.sjtu.edu.cn/nix-channels/store/$(basename "$P").narinfo"
  nix.settings = {
    substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    ];

    # A mirror that is down should cost seconds, not the kernel's default TCP
    # timeout, before nix falls through to the next substituter.
    connect-timeout = 10;
  };

  system.stateVersion = "25.05";
}
