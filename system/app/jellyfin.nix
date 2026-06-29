{
  pkgs,
  username,
  ...
}: {
  # AMD OpenCL for tone mapping
  hardware.graphics.extraPackages = with pkgs; [
    libva
    libva-vdpau-driver
    libvdpau-va-gl
    rocmPackages.clr.icd
  ];
  
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
  environment.systemPackages = with pkgs; [
    # Server
    jellyfin
    jellyfin-web
    jellyfin-ffmpeg
  ];

  # Automatic downloading
  services = {
    bazarr = {
      enable = true;
      group = "users";
    };
    sonarr = {
      enable = true;
      group = "users";
    };
    radarr = {
      enable = true;
      group = "users";
    };
    seerr = {
      enable = true;
      openFirewall = true;
    };
    prowlarr.enable = true;
  };

  # VPN namespace for torrenting
  vpnNamespaces.wg0 = {
    enable = true;
    wireguardConfigFile = "/home/${username}/proton-vpn.conf";
    portMappings = [
      {
        from = 9091;
        to = 9091;
      }
    ];
  };

  # Attach the transmission systemd service to the VPN namespace
  systemd.services.transmission.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg0";
  };

  # Torrenting
  services.transmission = {
    enable = true;
    group = "users";
    package = pkgs.transmission_4;
    settings = {
      download-dir = "/Vault/Downloads";
      incomplete-dir = "/Vault/Downloads/.incomplete";
      incomplete-dir-enabled = true;
      umask = "002";
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist-enabled = false;
      seed_ratio_limit = 0;
      seed_ratio_limited = true;
    };
  };
}
