# The acquisition suite: the *arr applications, the indexer manager that feeds
# them, the Cloudflare bypass one of those indexers needs, and the subtitle
# service that completes what they import.
{
  config,
  lib,
  ...
}: let
  stack = import ./layout.nix {inherit config lib;};
in {
  config = lib.mkIf stack.enabled {
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
      lidarr = {
        enable = true;
        group = "users";
      };
      prowlarr.enable = true;

      # Bypass Cloudflare on protected indexers (e.g. 1337x).
      # Point Prowlarr at http://127.0.0.1:8191 as a FlareSolverr proxy.
      flaresolverr.enable = true;
    };

    systemd.services = {
      sonarr.serviceConfig = stack.vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"];
      radarr.serviceConfig = stack.vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"];
      lidarr.serviceConfig = stack.vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"];
      bazarr.serviceConfig = stack.vaultRw ["/Vault/Jellyfin" "/Vault/Downloads"];
      # Neither talks to the library: Prowlarr only searches indexers and hands
      # results to the applications, and FlareSolverr only answers HTTP.
      prowlarr.serviceConfig = stack.vaultRw [];
      flaresolverr.serviceConfig = stack.vaultRw [];
    };

    # Every *arr app points Transmission at its own per-category directory
    # (/Vault/Downloads/radarr, .../tv-sonarr, .../lidarr) and Transmission
    # finishes a torrent by moving it out of .incomplete into that directory.
    # If the directory is not group-writable the move fails with EACCES, the
    # finished data is stranded in .incomplete, and the *arr apps log
    # "path does not exist or is not accessible" forever while the download
    # vanishes from their view. Keep them group-writable with the setgid bit so
    # files created inside keep the shared `users` group.
    systemd.tmpfiles.rules = [
      "d /Vault/Downloads 2775 root users -"
      "d /Vault/Downloads/.incomplete 2775 root users -"
      "d /Vault/Downloads/radarr 2775 root users -"
      "d /Vault/Downloads/tv-sonarr 2775 root users -"
      "d /Vault/Downloads/lidarr 2775 root users -"
    ];
  };
}
