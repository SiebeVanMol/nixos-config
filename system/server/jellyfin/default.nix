# Media server stack. One file per concern, all behind the single
# device.app.jellyfin.enable toggle:
#
#   jellyfin.nix      the media server itself (public)
#   acquisition.nix   Sonarr, Radarr, Lidarr and Bazarr, plus Prowlarr and
#                     FlareSolverr which feed them
#   downloads.nix     Transmission, confined to a ProtonVPN namespace
#   requests.nix      SeerrNG, the request front end (public)
#   reading.nix       Kavita, the reading server (LAN only)
#   dashboard.nix     Homepage, one landing page for everything above
#   proxy.nix         the Caddy virtual hosts and the hosts-file entries
#   servarr-sync.nix  converges the applications' own settings from Nix
#   recyclarr.nix     applies the TRaSH Guides quality profiles
#
# There is deliberately no book/comic ACQUISITION module. Readarr, Kapowarr and
# Shelfmark were tried and removed: Readarr's line was archived upstream and its
# metadata provider died with it, so the revival (bookshelf) needed a hand-built
# .NET 6 application pinned to two insecure packages and a hand-written unit for
# a project with no NixOS module - and in the end it had produced no files at
# all. SeerrNG's book requests therefore stop at the request itself; movies, TV
# and music are unaffected. The books and comics already in the library are read
# through Kavita and Jellyfin, which is what reading.nix is for.
#
# layout.nix holds what all of these share - the service/port table the reverse
# proxy and the hosts file are built from, and the `vaultRw` hardening helper -
# and each module pulls it in with `import ./layout.nix {inherit config lib;}`.
#
# The parts are listed below rather than globbed by lib/import-dir.nix, which is
# how system/app does it: layout.nix is a plain function, not a module, so a
# glob would try to import it and fail. Listing them is also the table of
# contents.
{
  imports = [
    ./jellyfin.nix
    ./acquisition.nix
    ./downloads.nix
    ./requests.nix
    ./reading.nix
    ./dashboard.nix
    ./proxy.nix
    ./servarr-sync.nix
    ./recyclarr.nix
  ];
}
