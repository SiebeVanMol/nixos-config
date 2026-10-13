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

  # Binary caches. This machine is in Japan; both are East Asian mirrors of
  # cache.nixos.org, listed first because a rebuild from nothing otherwise waits
  # on the official cache from Tokyo. nixpkgs appends cache.nixos.org after them
  # (mkAfter in nixos/modules/config/nix.nix), so it remains the fallback.
  #
  # Nothing new is trusted: same NARs, same cache.nixos.org-1 signatures,
  # require-sigs still on, key unchanged. Per-host, so Europe is untouched.
  #
  # If one turns out slow from Tokyo, measure before reordering - the other worth
  # trying is mirrors.ustc.edu.cn. A narinfo is a few hundred bytes, so fetch the
  # URL it names rather than timing the narinfo:
  #   U=$(curl -s "$m/$B.narinfo" | sed -n 's/^URL: //p')
  #   curl -so /dev/null -w "$m %{speed_download} B/s\n" "$m/$U"  # timed download
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
