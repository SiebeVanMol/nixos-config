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
#   books.nix         the ebook/comic acquisition chain, parked by default
#   servarr-sync.nix  converges the applications' own settings from Nix
#   recyclarr.nix     applies the TRaSH Guides quality profiles
#
# The ebook/comic ACQUISITION chain is parked behind its own
# device.app.books.enable toggle (off by default) because it had produced no
# files at all while being the most fragile part of the stack:
#
#   Readarr       ebooks - the only backend SeerrNG can hand book requests to
#   Kapowarr      comics
#   Shelfmark     ebook/manga acquisition, driven by Prowlarr
#
# Note that SeerrNG's book requests stop at the request itself while that chain
# is parked; movies, TV and music are unaffected.
#
# layout.nix holds what all of these share - the service/port table the reverse
# proxy and the hosts file are built from, the books toggle, and the `vaultRw`
# hardening helper - and each module pulls it in with
# `import ./layout.nix {inherit config lib;}`.
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
    ./books.nix
    ./servarr-sync.nix
    ./recyclarr.nix
  ];
}
