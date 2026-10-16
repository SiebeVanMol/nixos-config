# Bazarr: subtitles.
{
  config,
  lib,
  media,
  ...
}: let
  arrApps = import ../../../lib/arr-apps.nix {inherit lib;};
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    services.bazarr = {
      enable = true;
      group = "users";

      # The web UI requires a login. Without it Bazarr hands its API key to any
      # request it considers local, and behind the reverse proxy every LAN
      # request arrives from 127.0.0.1 - measured with no credentials:
      #
      #   curl -H 'Host: bazarr.lan' http://127.0.0.1/initialize.json
      #
      # `_secret` is the module's own mechanism: systemd reads that file (root
      # only) and passes its contents to the unit, so the password never reaches
      # the store. Bazarr's auth type is "form" where the *arr applications say
      # "forms", and its API keeps using the api key either way.
      settings.auth = {
        type = "form";
        username = arrApps.uiAuth.username;
        password._secret = arrApps.uiAuth.passwordFile;
      };
    };

    # Subtitles are written next to the library media, wherever it is; it reads
    # downloads too.
    systemd.services.bazarr.serviceConfig = media.vaultRw [media.mediaRoot media.downloads];

    device.media.services.bazarr = {
      port = 6767;
      dashboard = {
        group = "acquisition";
        order = 50;
        title = "Bazarr";
        description = "Subtitles";
        widget = {
          type = "bazarr";
          keyVar = "HOMEPAGE_VAR_BAZARR_KEY";
        };
      };
      # 1.6 moved settings from config.ini to config.yaml; the whole config
      # directory is copied either way.
      backup = {
        sqliteRoots = ["/var/lib/bazarr"];
        statePaths = ["/var/lib/bazarr/config"];
      };
    };
  };
}
