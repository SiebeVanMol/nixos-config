# Navidrome: the music server, over the /Vault/Media/music tree slskd fills.
#
# Jellyfin can serve music, but it is a video server that also handles audio.
# Navidrome is built around music: it speaks Subsonic/OpenSubsonic, so every
# mobile client works, and it has smart playlists, per-user now-playing,
# scrobbling and a scanner that is happy with a six-figure track count.
#
# It only ever READS the library - slskd writes it - and it cannot make an
# exception: the module runs it in a minimal RootDirectory chroot with the
# music folder bind-mounted read-only, so a bug or a bad plugin cannot touch a
# file. Its own database, cache and transcodes live under /var/lib/navidrome.
{
  config,
  lib,
  media,
  ...
}: {
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
