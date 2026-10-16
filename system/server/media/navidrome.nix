# Navidrome: the music server, over the /Vault/Media/music tree slskd fills.
#
# Jellyfin can serve music but is a video server; Navidrome speaks
# Subsonic/OpenSubsonic, so every mobile client works, and has smart playlists,
# scrobbling and a scanner that handles six-figure track counts. It only ever
# READS the library: the module runs it in a minimal chroot with the music
# folder bind-mounted read-only.
{
  config,
  lib,
  media,
  ...
}: {
  # Declared here rather than derived from the tree, because the two names
  # differ: this module is server/media/navidrome.nix and its toggle is
  # device.app.music.
  options.device.app.music.enable = lib.mkEnableOption "Navidrome music server with slskd (Soulseek) acquisition";

  # The music stack has its own toggle; it does not need Jellyfin.
  config = lib.mkIf config.device.app.music.enable {
    services.navidrome = {
      enable = true;
      # The module's PrivateUsers=true only maps the unit's own user and group
      # into the namespace; the shared `users`-group library tree would be
      # nobody's otherwise. Making `users` the primary group is what keeps
      # 2775 root:users readable here.
      group = "users";

      settings = {
        # Caddy fronts it on navidrome.lan / navidrome.<publicDomain>.
        Address = "127.0.0.1";
        Port = 4533;
        MusicFolder = media.musicLibrary;

        # Spelled out rather than left to the defaults: the module only binds
        # a folder into the chroot when the setting is present, so these being
        # explicit is what puts them at the paths the defaults name.
        DataFolder = "/var/lib/navidrome";
        CacheFolder = "/var/lib/navidrome/cache";

        # No telemetry for a self-hosted music server.
        EnableInsightsCollector = false;
      };
    };

    device.media.services.navidrome = {
      port = 4533;
      # Public like Jellyfin: it has its own login and listening outside the
      # house is the point of a music server.
      public = true;
      dashboard = {
        group = "library";
        order = 20;
        title = "Navidrome";
        description = "Listen";
      };
      backup.sqliteRoots = ["/var/lib/navidrome"];
    };
  };
}
