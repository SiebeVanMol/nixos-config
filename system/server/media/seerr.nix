# SeerrNG: the request front end, and one of the two parts of this stack that
# friends and family see.
{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable {
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

    # Requests front end, served through Caddy; no direct port. SeerrNG reuses the
    # upstream module (same PORT/CONFIG_DIRECTORY contract), so only the binary
    # swaps. stateRevision = 1 selects /var/lib/seerr instead of the legacy
    # /var/lib/jellyseerr/config, whose DynamicUser symlink its path guard
    # rejects.
    services.seerr = {
      enable = true;
      package = pkgs.seerrng;
      stateRevision = 1;
    };

    # Deliberately absent from the vaultRw list: the module already sets
    # ProtectSystem="strict", which vaultRw would downgrade to "full" while
    # adding a /Vault rule Seerr never uses. DynamicUser must be off, though:
    # SeerrNG refuses a config path containing a symlink, and DynamicUser always
    # publishes StateDirectory as a /var/lib/private symlink.
    systemd.services.seerr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "seerr";
    };

    device.media.services.seerr = {
      port = 5055;
      public = true;
      dashboard = {
        group = "library";
        order = 30;
        title = "Seerr";
        description = "Requests";
        widget = {
          type = "seerr";
          keyVar = "HOMEPAGE_VAR_SEERR_KEY";
        };
      };
      backup = {
        sqliteRoots = ["/var/lib/seerr"];
        statePaths = ["/var/lib/seerr/settings.json"];
      };
    };
  };
}
