# Media server stack: Jellyfin (media), Sonarr (TV), Radarr (movies), Bazarr (subtitles),
# Prowlarr (indexers), Overseerr (requests), and Transmission (torrents) confined to a ProtonVPN namespace.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  # Services exposed through the reverse proxy: name → local port.
  sites = [
    { name = "jellyfin"; port = 8096; }
    { name = "sonarr"; port = 8989; }
    { name = "radarr"; port = 7878; }
    { name = "bazarr"; port = 6767; }
    { name = "prowlarr"; port = 9696; }
    { name = "overseerr"; port = 5055; }
    { name = "transmission"; port = 9091; }
    { name = "flaresolverr"; port = 8191; }
  ];

  # One Caddy virtual host per site per domain. LAN hosts are plain HTTP,
  # public hosts get automatic HTTPS via the HTTP-01 challenge.
  mkHost = scheme: suffix: site: {
    name = scheme + site.name + suffix;
    value = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString site.port}
      '';
    };
  };
  mkLanVhost = mkHost "http://" ".lan";
  mkPublicVhost = mkHost "" ".${config.device.security.reverse-proxy.publicDomain}";

  lanHosts = [ "jellyfin.lan" "sonarr.lan" "radarr.lan" "bazarr.lan" "prowlarr.lan" "overseerr.lan" "transmission.lan" "flaresolverr.lan" ];
in {
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

    # Reverse proxy every service on its own subdomain.
    # *.lan is plain HTTP for the local network; *.snowyrenard.com is HTTPS for friends.
    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable (lib.listToAttrs (
      (map mkLanVhost sites)
      ++ lib.optionals (config.device.security.reverse-proxy.publicDomain != "") (map mkPublicVhost sites)
    ));

    networking.hosts = lib.mkMerge [
      {
        "172.67.188.67" = [ "1337x.to" ];
        "104.21.40.193" = [ "1337x.to" ];
      }
      (lib.mkIf config.device.security.reverse-proxy.enable {
        "127.0.0.1" = lanHosts;
      })
    ];
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

