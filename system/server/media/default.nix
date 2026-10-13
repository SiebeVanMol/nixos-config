# Media server stack: the video/book stack behind device.app.jellyfin.enable,
# the music stack behind device.app.music.enable, and the plumbing they share.
#
# Every .nix file here is glob-imported (lib/import-dir.nix), so adding a service
# is adding one file. A service gates itself on its own toggle and registers in
# device.media.services; options.nix, vpn.nix, paths.nix, proxy.nix, homepage.nix
# and dashboard.nix read that registry. The remaining files are one per service,
# plus servarr-sync (converges *arr settings), recyclarr (TRaSH profiles),
# soularr (Lidarr -> slskd) and torrent-cleanup.
#
# There is deliberately no book/comic ACQUISITION module: Readarr, Kapowarr and
# Shelfmark were tried and removed without producing a single file. SeerrNG book
# requests stop at the request; books and comics already in the library are read
# through Kavita and Jellyfin.
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
