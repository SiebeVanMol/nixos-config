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
  # `public = true` additionally publishes the service on *.${publicDomain}.
  # Keep ONLY Jellyfin and Seerr public; the rest of the *arr suite, Transmission
  # and FlareSolverr are sensitive admin/management UIs and stay LAN/Tailscale-only.
  sites = [
    { name = "jellyfin"; port = 8096; public = true; }
    { name = "sonarr"; port = 8989; }
    { name = "radarr"; port = 7878; }
    { name = "bazarr"; port = 6767; }
    { name = "prowlarr"; port = 9696; }
    { name = "seerr"; port = 5055; public = true; }
    { name = "transmission"; port = 9091; }
    { name = "flaresolverr"; port = 8191; }
  ];

  publicSites = lib.filter (s: s ? public && s.public) sites;

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

  lanHosts = [ "jellyfin.lan" "sonarr.lan" "radarr.lan" "bazarr.lan" "prowlarr.lan" "seerr.lan" "transmission.lan" "flaresolverr.lan" ];
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # AMD OpenCL for tone mapping
    hardware.graphics.extraPackages = lib.mkIf config.device.hardware.amd.enable [
      pkgs.libva
      pkgs.libva-vdpau-driver
      pkgs.libvdpau-va-gl
      pkgs.rocmPackages.clr.icd
    ];

    # Jellyfin is reachable only through the Caddy reverse proxy (ports 80/443),
    # so no direct firewall port is opened here.
    services.jellyfin.enable = true;

    # Give each service write access only to its own directories on /Vault and
    # make the rest of /Vault read-only, so a compromised app can't touch other
    # users' files. ProtectSystem="full" keeps /var/lib (app config) writable.
    #   - jellyfin:  its own media library
    #   - sonarr/radarr: ingest completed downloads, import into the library
    #   - bazarr:    subtitles next to library media
    #   - transmission: completed downloads
    #   - prowlarr/seerr/flaresolverr: no /Vault write access
    systemd.services = let
      vaultRw = writable: {
        ProtectSystem = lib.mkForce "full";
        ReadOnlyPaths = [ "/Vault" ];
        ReadWritePaths = writable;
      };
    in {
      jellyfin.serviceConfig = vaultRw [ "/Vault/Jellyfin" ];
      sonarr.serviceConfig = vaultRw [ "/Vault/Downloads" "/Vault/Jellyfin" ];
      radarr.serviceConfig = vaultRw [ "/Vault/Downloads" "/Vault/Jellyfin" ];
      bazarr.serviceConfig = vaultRw [ "/Vault/Jellyfin" "/Vault/Downloads" ];
      transmission.serviceConfig = vaultRw [ "/Vault/Downloads" ];
      prowlarr.serviceConfig = vaultRw [ ];
      seerr.serviceConfig = vaultRw [ ];
      flaresolverr.serviceConfig = vaultRw [ ];

      # Attach the transmission systemd service to the VPN namespace.
      transmission.vpnConfinement = {
        enable = true;
        vpnNamespace = "wg0";
      };
    };

    # Reverse proxy every service on its own subdomain.
    # *.lan is plain HTTP for the local network; only Jellyfin gets a public
    # HTTPS subdomain on *.${publicDomain} for friends.
    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable (lib.listToAttrs (
      (map mkLanVhost sites)
      ++ lib.optionals (config.device.security.reverse-proxy.publicDomain != "") (map mkPublicVhost publicSites)
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
      # Overseerr is served through Caddy too; no direct port opened.
      seerr.enable = true;
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

