# Media server stack: the video/book stack behind device.app.jellyfin.enable,
# the music stack behind device.app.music.enable, and the plumbing they share.
#
# Every .nix file in this directory is a module and is imported automatically
# (lib/import-dir.nix), so adding a service is adding one file here - there is
# no import list to remember to update, and no second list of ports or paths to
# keep in step. A service module gates itself on its own toggle and registers
# itself in device.media.services; the shared consumers read that registry:
#
#   options.nix       the device.media service registry (what a service
#                     declares about itself, once)
#   vpn.nix           the WireGuard namespace every download client shares
#   paths.nix         the /Vault directories derived from the registry, and the
#                     sweep that keeps everything written inside them readable
#                     and writable by the shared `users` group
#   proxy.nix         Caddy vhosts and hosts entries, derived from the registry
#   homepage.nix      the Homepage application and its API-key collector
#   dashboard.nix     the dashboard tiles, derived from the registry
#
#   jellyfin.nix, navidrome.nix, soulseek.nix, transmission.nix, sonarr.nix,
#   radarr.nix, lidarr.nix, bazarr.nix, prowlarr.nix, flaresolverr.nix,
#   kavita.nix, seerr.nix, houndarr.nix
#                     one file per service
#   servarr-sync.nix  converges the *arr applications' own settings
#   recyclarr.nix     applies the TRaSH Guides quality profiles
#   soularr.nix       bridges Lidarr's wanted list to slskd, so Soulseek
#                     downloads are imported and managed by Lidarr
#   torrent-cleanup.nix
#                     removes long-stalled torrents and asks the *arr
#                     application that wanted them to search again
#
# There is deliberately no book/comic ACQUISITION module. Readarr, Kapowarr and
# Shelfmark were tried and removed: Readarr's line was archived upstream and its
# metadata provider died with it, so the revival (bookshelf) needed a hand-built
# .NET 6 application pinned to two insecure packages and a hand-written unit for
# a project with no NixOS module - and in the end it had produced no files at
# all. SeerrNG's book requests therefore stop at the request itself; movies, TV
# and music are unaffected. The books and comics already in the library are read
# through Kavita and Jellyfin, which is what kavita.nix is for.
{lib, ...}: let
  importDir = import ../../../lib/import-dir.nix {inherit lib;};
in {
  imports = importDir ./.;

  # The /Vault layout and vaultRw helper live in lib/media.nix, handed to every
  # module as the `media` specialArg (see flake.nix) so each one takes it
  # directly instead of repeating the import line. It is a specialArg and not
  # _module.args because a service module uses `media` inside its own `config`,
  # which would otherwise recurse through the config fixed point.
}
