{
  pkgs,
  lib,
  ...
}: {

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
      openFirewall = true;
    };
    sonarr = {
      enable = true;
      group = "users";
      openFirewall = true;
    };
    radarr = {
      enable = true;
      group = "users";
      openFirewall = true;
    };
    seerr = {
      enable = true;
      openFirewall = true;
    };
    prowlarr.enable = true;
  };
  # Fix file permissions
  systemd.services = builtins.listToAttrs (map (name: {
  inherit name;
  value.serviceConfig.UMask = lib.mkForce "0002";
  }) [ "radarr" "sonarr" "bazarr" ]);
}
