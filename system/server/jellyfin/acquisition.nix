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

      # Every *arr app keeps its API key in config.xml inside its data
      # directory, and that key is a full admin credential - it bypasses the web
      # login entirely. Sonarr's directory was created 0755 (its siblings are
      # 0700), which let any local account read the key out of it and take over
      # the whole app. Pin all three to 0700 so only the app's own user can
      # traverse into them; `z` leaves the owner and group alone.
      "z /var/lib/sonarr/.config/NzbDrone 0700 - - -"
      "z /var/lib/radarr/.config/Radarr 0700 - - -"
      "z /var/lib/lidarr/.config/Lidarr 0700 - - -"
    ];
  };
}
