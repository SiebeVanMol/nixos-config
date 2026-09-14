# The parked ebook/comic acquisition chain.
#
# device.app.books.enable is off by default, and this whole file is why: it is
# the most fragile part of the stack - a hand-built .NET 6 application pinned to
# two insecure packages, plus a hand-written unit for a project with no NixOS
# module - and it had produced no files at all. Everything here is gated so that
# a parked chain costs nothing: no services, no vhosts, no hosts entries, no
# accounts, no /Vault directories, and no insecure-package allowance.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stack = import ./layout.nix {inherit config lib;};
in {
  config = lib.mkIf stack.enabled {
    # Kapowarr (comic books) ships no NixOS module, so its account and unit are
    # defined by hand. It belongs to the shared `users` group like the rest of
    # the stack so it can hand files to/from Transmission and Jellyfin.
    users.users.kapowarr = lib.mkIf stack.booksEnabled {
      isSystemUser = true;
      group = "users";
      home = "/var/lib/kapowarr";
    };

    # Shelfmark (ebooks) likewise runs under its own account in the shared
    # `users` group; see the serviceConfig override below for why it cannot use
    # the nixpkgs module's default DynamicUser.
    users.users.shelfmark = lib.mkIf stack.booksEnabled {
      isSystemUser = true;
      group = "users";
      home = "/var/lib/shelfmark";
    };

    services = {
      # SeerrNG's book backend - the ONLY service it can hand a book request to.
      # Its book integration is the Readarr API (routes/settings/readarr.js,
      # api/servarr/readarr.js, lib/scanners/readarr), and it has no Shelfmark
      # support whatsoever. Without a Readarr-shaped instance a book request
      # stops in SeerrNG and is never downloaded:
      #
      #   SeerrNG request -> Readarr -> Prowlarr indexers -> Transmission
      #
      # Upstream Readarr/Readarr was retired and archived, and its metadata died
      # with it: every lookup went through api.bookinfo.club, a Goodreads proxy
      # that no longer answers, so author and book searches return nothing and
      # the service is useless to SeerrNG. The package is therefore overridden
      # with `pkgs.bookshelf` (see overlays/bookshelf.nix), the maintained
      # revival of the same codebase. It keeps the Readarr name on its binary
      # and reports appName "Readarr" on /api/v1/system/status - which is what
      # SeerrNG's client keys off (it only special-cases "chaptarr") - so this
      # swap needs no change on the SeerrNG side.
      #
      # `readarrMetadataUrl` (layout.nix) selects the metadata service. The
      # default is the one bookshelf ships with: Goodreads-derived but working,
      # and compatible with an existing Readarr database, so this is a drop-in
      # replacement and the SeerrNG link (URL + API key) keeps working untouched.
      # Pointing it at https://hardcover.bookinfo.pro instead switches the
      # instance to Hardcover, whose metadata is much higher quality - but that
      # mode is NOT backward compatible with a Readarr database, so it also
      # means deleting /var/lib/readarr and re-entering indexers, the
      # Transmission download client, the /Vault/Jellyfin/Books/Books root
      # folder, and the new API key in SeerrNG.
      #
      # In Readarr set: download client = Transmission (via the wg0 namespace
      # address, as in the `sites` entry in layout.nix), indexers = Prowlarr, and
      # root folder = /Vault/Jellyfin/Books/Books. That root is shared with
      # Shelfmark's INGEST_DIR; both organise as Author/Title so they coexist,
      # but a title fetched by both lands twice - prefer SeerrNG for requested
      # books and Shelfmark's own UI for manga and raw Nyaa releases.
      readarr = lib.mkIf stack.booksEnabled {
        enable = true;
        group = "users";
        package = pkgs.bookshelf;
      };

      # Ebook search/request front end. Ingest goes straight into the existing
      # Jellyfin library tree, organised as Author/Title (Year), so Jellyfin
      # picks new books up on its own.
      shelfmark = lib.mkIf stack.booksEnabled {
        enable = true;
        environment = {
          FLASK_HOST = "127.0.0.1";
          FLASK_PORT = 8084;
          CONFIG_DIR = "/var/lib/shelfmark";
          INGEST_DIR = "/Vault/Jellyfin/Books/Books";
          FILE_ORGANIZATION = "organize";

          # Japanese manga is reached through Prowlarr - which already carries
          # Nyaa.si - rather than through a book metadata provider, because the
          # ISBN-based providers do not index raw/scanlation releases at all.
          # AUTO_EXPAND is what makes this work: Nyaa's manga releases are not
          # filed under the standard book category (7000), so a category-filtered
          # search returns nothing and the retry without filtering is required.
          # PROWLARR_INDEXERS is deliberately unset (search all indexers); list
          # just the Nyaa entry there if the general indexers add noise.
          PROWLARR_ENABLED = "true";
          PROWLARR_URL = "http://127.0.0.1:9696";
          PROWLARR_AUTO_EXPAND = "true";
        };
      };
    };

    systemd.services = {
      readarr.serviceConfig = lib.mkIf stack.booksEnabled (stack.vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"]);

      # The nixpkgs readarr/shelfmark modules instantiate their systemd unit for
      # every systemd.services.<name> key that exists at all, so an mkIf that
      # evaluates to nothing still leaves a start-less readarr.service behind
      # (no ExecStart, nothing wanting it). It is never started either way;
      # `enable = false` makes that policy explicit, so the unit cannot be
      # started even if something later acquires a reference to it. A no-op
      # while the chain is enabled.
      readarr.enable = lib.mkIf (!stack.booksEnabled) false;
      shelfmark.enable = lib.mkIf (!stack.booksEnabled) false;

      # bookshelf resolves metadata through METADATA_URL only when its own
      # MetadataSource setting is empty, which is the case on a fresh instance.
      # services.readarr already fills the unit's environment from the `settings`
      # option; this is merged on top of it. It MUST be assigned here rather
      # than as a second top-level `systemd.services.<name>...` line: that is
      # the same attribute `systemd.services` twice in one attrset, which Nix
      # rejects with "attribute already defined" before any module merging.
      readarr.environment = lib.mkIf stack.booksEnabled {
        METADATA_URL = stack.readarrMetadataUrl;
      };

      # Comic book manager, the *arr-shaped hole in the stack. Upstream has no
      # NixOS module, so the unit is written out here. It binds loopback only;
      # Caddy fronts it on kapowarr.lan like everything else.
      kapowarr = lib.mkIf stack.booksEnabled {
        description = "Kapowarr comic book library manager";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        serviceConfig = lib.mkMerge [
          {
            User = "kapowarr";
            Group = "users";
            StateDirectory = "kapowarr";
            WorkingDirectory = "/var/lib/kapowarr";
            Restart = "on-failure";
            # Kapowarr creates and downloads into its temp download folder at
            # startup, and its default location is inside the (read-only) store,
            # so this MUST point somewhere writable. It is also the folder handed
            # to Transmission, hence the shared group-writable location.
            ExecStart = "${pkgs.kapowarr}/bin/kapowarr -d /var/lib/kapowarr/db -l /var/lib/kapowarr/logs -t /Vault/Downloads/kapowarr -o 127.0.0.1 -p 5656";
          }
          (stack.vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"])
        ];
      };

      # The nixpkgs Shelfmark module runs it under DynamicUser with UMask 0077
      # inside a ProtectSystem="strict" sandbox. Both would break the shared
      # library: a dynamic UID is not a member of the `users` group, and 0077
      # files are unreadable by Jellyfin. Give it a real account in the shared
      # group instead. Note that strict mode makes /Vault read-only, so the
      # library paths below are required rather than optional.
      shelfmark.serviceConfig = lib.mkIf stack.booksEnabled {
        DynamicUser = lib.mkForce false;
        User = lib.mkForce "shelfmark";
        Group = lib.mkForce "users";
        UMask = lib.mkForce "0002";
        ReadWritePaths = [
          "/Vault/Jellyfin/Books"
          "/Vault/Downloads/shelfmark"
        ];
        # The Prowlarr API key is a secret, and `environment` values are written
        # into the world-readable Nix store, so it lives in a root-only file
        # instead (same pattern as the WireGuard config in /etc/wireguard). The
        # leading "-" keeps it optional so the service starts before the file
        # exists. systemd applies EnvironmentFile after Environment=, so a key
        # set here takes precedence over one set in the flake.
        EnvironmentFile = "-/etc/shelfmark/prowlarr.env";
      };
    };

    # bookshelf is still a .NET 6 application - its global.json pins the SDK and
    # the projects target net6.0 - and .NET 6 is out of support, so nixpkgs
    # marks both the SDK and the ASP.NET runtime as insecure. They are required
    # to build and to run it, and nothing else in this configuration pulls them
    # in, so the permission is granted for exactly these two store paths. If a
    # nixpkgs bump changes their versions, the build error names the new ones.
    #
    # Gated on the books toggle, so a parked stack needs no insecure packages
    # and a nixpkgs bump can no longer break evaluation because of them.
    nixpkgs.config.permittedInsecurePackages = lib.mkIf stack.booksEnabled [
      "dotnet-sdk-6.0.428"
      "aspnetcore-runtime-6.0.36"
    ];

    # The chain's folders. Kept (rather than deleted) so re-enabling
    # device.app.books comes back to the same layout; on a parked stack they are
    # simply never created.
    systemd.tmpfiles.rules = lib.optionals stack.booksEnabled [
      # Readarr ingests and imports into the same ebook root Shelfmark targets
      # (/Vault/Jellyfin/Books/Books); see the note on services.readarr below.
      "d /Vault/Downloads/readarr 2775 root users -"
      # Kapowarr's temp download folder: Transmission writes finished torrents
      # here, so it needs the same group-writable treatment as the others.
      "d /Vault/Downloads/kapowarr 2775 root users -"
      "d /Vault/Downloads/shelfmark 2775 root users -"
      # Kapowarr's root folder. It must be the Comics subfolder of the existing
      # library tree - the Hellboy PDFs already live there - so point the
      # Kapowarr UI at this path rather than letting it create a second, rival
      # Comics directory. Jellyfin reads it as "other", which 2775 preserves.
      "d /Vault/Jellyfin/Books/Comics 2775 root users -"
      # Shelfmark's ingest target (the ebooks subfolder); already present, kept
      # here so a fresh host converges on the same layout.
      "d /Vault/Jellyfin/Books/Books 2775 root users -"
    ];
  };
}
