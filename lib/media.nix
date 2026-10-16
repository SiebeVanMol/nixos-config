# The /Vault layout the media stack shares, plus the hardening helper every
# service in it uses.
#
# A plain function, not a module, so a service can pull in exactly these values
# without touching the module system (and so this directory can be glob-imported
# - every .nix file left in it is a real module).
#
# One tree, /Vault/Media, holds everything the servers present as media (films,
# shows, books, manga, music). It was /Vault/Jellyfin, named after the
# application that happened to own it, which stopped being true once Navidrome
# and Kavita served the same files. Naming every path here keeps a library move
# from becoming a hunt through a dozen files.
{lib}: let
  # The *arr application facts live in their own file, because the flake's own
  # commands need them too and have no host configuration to read
  # (lib/arr-apps.nix). Only the values more than one consumer wants are there.
  arrApps = import ./arr-apps.nix {inherit lib;};
in rec {
  # "sonarr" -> "Sonarr", for the names the *arr APIs and their directories use.
  inherit (arrApps) capitalize;

  vault = "/Vault";

  mediaRoot = "${vault}/Media";
  movies = "${mediaRoot}/Movies";
  shows = "${mediaRoot}/Shows";
  books = "${mediaRoot}/Books";
  manga = "${mediaRoot}/Manga";

  # Music keeps its original capitalisation, so the old /Vault/Jellyfin tree maps
  # name-for-name and a migration symlink keeps every existing absolute path in
  # Sonarr/Radarr/Lidarr/Jellyfin/Kavita working untouched.
  musicLibrary = "${mediaRoot}/Music";

  # Torrent staging shared by Transmission and the *arr applications.
  downloads = "${vault}/Downloads";

  # Soulseek's two directories: partial files wait in the staging dir, finished
  # downloads land for Lidarr (via Soularr) to import. Staging is deliberately
  # outside the library so files do not appear there unmanaged and invisible.
  musicIncomplete = "${mediaRoot}/.incomplete";
  musicDownloads = "${mediaRoot}/downloads";

  # Give a service write access only to its own directories on /Vault and make the
  # rest read-only, so a compromised app cannot touch another service's files.
  # ProtectSystem="full" keeps /var/lib writable.
  #
  # The whole stack runs in the shared `users` group and hands files to each other
  # through /Vault, so UMask is forced to 0002: the upstream modules pin 0022,
  # which makes anything they create group-read-only and stops the next service
  # from writing it.
  vaultRw = writable: {
    ProtectSystem = lib.mkForce "full";
    ReadOnlyPaths = ["/Vault"];
    ReadWritePaths = writable;
    UMask = lib.mkForce "0002";
  };

  # The three *arr applications differ only in the values below. The unit, the
  # 0700 config directory that guards the API key in config.xml, and the registry
  # entry the proxy, dashboard and backup read are one shape, so they are built
  # here instead of copied into each module.
  #
  # `projectDir` is the directory the application nests under .config: the API's
  # own project name, "NzbDrone" for Sonarr and the application name for the rest.
  mkArr = {
    name,
    port,
    order,
    description,
    category,
    writePaths,
    projectDir ? capitalize name,
  }: let
    implementation = capitalize name;
  in {
    services.${name} = {
      enable = true;
      group = "users";
    };

    # Ingest downloads and import into the library paths the application owns.
    systemd.services.${name}.serviceConfig = vaultRw writePaths;

    # The API key in config.xml is a full admin credential - it bypasses the
    # web login entirely - so the directory is pinned to 0700; `z` leaves the
    # owner and group alone.
    systemd.tmpfiles.rules = [
      "z /var/lib/${name}/.config/${projectDir} 0700 - - -"
    ];

    device.media.services.${name} = {
      inherit port;
      dashboard = {
        group = "acquisition";
        inherit order description;
        title = implementation;
        widget = {
          type = name;
          keyVar = "HOMEPAGE_VAR_${lib.toUpper name}_KEY";
        };
      };
      servarr = {
        inherit implementation category;
        dir = "/var/lib/${name}";
      };
      backup = {
        sqliteRoots = ["/var/lib/${name}"];
        statePaths = ["/var/lib/${name}/config.xml"];
      };
    };
  };
}
