# SeerrNG: the request front end, and the only part of this stack that friends
# and family see.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stack = import ./layout.nix {inherit config lib;};
in {
  config = lib.mkIf stack.enabled {
    # SeerrNG needs an ordinary (non-dynamic) account so that its state
    # directory is a real path rather than a symlink; see the serviceConfig
    # override below. It needs no /Vault access, so it stays out of the shared
    # `users` group.
    users.users.seerr = {
      isSystemUser = true;
      group = "seerr";
      home = "/var/lib/seerr";
    };
    users.groups.seerr = {};

    # Requests front end, served through Caddy too; no direct port opened.
    # SeerrNG is the fork of Seerr that extends the movies/TV request workflow
    # to music, ebooks and audiobooks. It reuses the upstream module - the
    # service honours the same PORT/CONFIG_DIRECTORY contract - so only the
    # binary swaps. stateRevision = 1 selects the current config location
    # (/var/lib/seerr, a real directory) instead of the legacy
    # /var/lib/jellyseerr/config, whose parent is a DynamicUser symlink that
    # SeerrNG's path guard rejects.
    services.seerr = {
      enable = true;
      package = pkgs.seerrng;
      stateRevision = 1;
    };

    # seerr is deliberately absent from the vaultRw list. Its module already
    # sets ProtectSystem="strict", whereas vaultRw force-downgrades that to
    # "full" while adding a /Vault rule it has no use for: Seerr only ever talks
    # to Jellyfin and the *arr APIs over HTTP. Leaving the module's own (strict)
    # setting alone is both simpler and tighter.
    #
    # It does need DynamicUser turned off, though. SeerrNG refuses to use a
    # config path containing a symlink (a symlink-attack guard it adds on top of
    # upstream), and systemd's DynamicUser always publishes StateDirectory as
    # /var/lib/<name> -> /var/lib/private/<name>. A real account makes
    # /var/lib/seerr an ordinary directory, which satisfies the guard.
    systemd.services.seerr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "seerr";
    };
  };
}
