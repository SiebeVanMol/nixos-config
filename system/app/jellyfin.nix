# Media server stack: Jellyfin (media), Sonarr (TV), Radarr (movies), Bazarr (subtitles),
# Prowlarr (indexers), Overseerr (requests), and Transmission (torrents) confined to a ProtonVPN namespace.
{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # AMD OpenCL for tone mapping
    hardware.graphics.extraPackages = lib.mkIf config.device.hardware.amd.enable [
      pkgs.libva
      pkgs.libva-vdpau-driver
      pkgs.libvdpau-va-gl
      pkgs.rocmPackages.clr.icd
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

      # Bypass Cloudflare on protected indexers (e.g. 1337x).
      # Point Prowlarr at http://127.0.0.1:8191 as a FlareSolverr proxy.
      flaresolverr.enable = true;
    };

    # ISP DNS (Telenet) sinkholes 1337x.to, so pin it to its Cloudflare IPs.
    # Update these if Cloudflare rotates the addresses.
    networking.hosts = {
      "172.67.188.67" = [ "1337x.to" ];
      "104.21.40.193" = [ "1337x.to" ];
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
  };
}

