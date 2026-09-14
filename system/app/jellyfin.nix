# Media server stack, all behind the single device.app.jellyfin.enable toggle:
#
#   Homepage      dashboard: one landing page for everything below (LAN only)
#   Jellyfin      media server and player (public)
#   SeerrNG       request front end for movies, TV, music and books (public)
#   Sonarr        TV
#   Radarr        movies
#   Lidarr        music
#   Bazarr        subtitles
#   Kavita        reading server over the ebook/comic library (LAN only)
#   Prowlarr      indexers
#   FlareSolverr  Cloudflare bypass for Prowlarr
#   Transmission  torrent client, confined to a ProtonVPN namespace
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
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Services exposed through the reverse proxy: name → local port.
  # `public = true` additionally publishes the service on *.${publicDomain}.
  # Keep ONLY Jellyfin and Seerr public; every other entry here (the *arr suite,
  # Transmission, FlareSolverr, Kapowarr, Shelfmark, Kavita) is a
  # sensitive admin/management UI and stays LAN/Tailscale-only.
  sites = [
    # The dashboard is the landing page for the whole stack: one place to look
    # instead of remembering a dozen *.lan names. It is declared as a site like
    # anything else, and configured in system/app/homepage.nix.
    {
      name = "home";
      port = 8082;
    }
    {
      name = "jellyfin";
      port = 8096;
      public = true;
    }
    {
      name = "sonarr";
      port = 8989;
    }
    {
      name = "radarr";
      port = 7878;
    }
    {
      name = "lidarr";
      port = 8686;
    }
    {
      name = "readarr";
      port = 8787;
    }
    {
      name = "bazarr";
      port = 6767;
    }
    {
      name = "prowlarr";
      port = 9696;
    }
    {
      name = "seerr";
      port = 5055;
      public = true;
    }
    {
      name = "transmission";
      port = 9091;
      # Transmission's RPC socket lives inside the WireGuard namespace, not on
      # the host. VPN-Confinement forwards the mapped port with a nat/PREROUTING
      # DNAT rule, and locally generated traffic never traverses PREROUTING, so
      # the host cannot reach it over 127.0.0.1 and this vhost would return 502.
      # Address the namespace's veth peer directly; that is also how
      # Sonarr/Radarr already reach Transmission.
      host = config.vpnNamespaces.wg0.namespaceAddress;
    }
    {
      name = "flaresolverr";
      port = 8191;
    }
    {
      name = "kapowarr";
      port = 5656;
    }
    {
      name = "shelfmark";
      port = 8084;
    }
    {
      name = "kavita";
      port = 5000;
    }
  ];

  # The ebook/comic chain is parked by default: see device.app.books in
  # options.nix. Its entries stay listed here rather than being deleted, so
  # flipping the toggle back on restores the vhosts and the .lan names too, but
  # a parked stack publishes no dead vhosts and adds no dead hosts entries.
  bookSiteNames = ["readarr" "kapowarr" "shelfmark"];

  booksEnabled = config.device.app.books.enable;

  activeSites = lib.filter (s: booksEnabled || !(lib.elem s.name bookSiteNames)) sites;

  publicSites = lib.filter (s: s ? public && s.public) activeSites;

  # One Caddy virtual host per site per domain. LAN hosts are plain HTTP,
  # public hosts get automatic HTTPS via the HTTP-01 challenge.
  mkHost = scheme: suffix: site: {
    name = scheme + site.name + suffix;
    value = {
      extraConfig = ''
        reverse_proxy ${site.host or "127.0.0.1"}:${toString site.port}
      '';
    };
  };
  mkLanVhost = mkHost "http://" ".lan";
  mkPublicVhost = mkHost "" ".${config.device.security.reverse-proxy.publicDomain}";

  # Derived from `sites` rather than listed again: one place to add a service,
  # and a parked service cannot leave a stale *.lan name behind.
  lanHosts = map (s: s.name + ".lan") activeSites;

  # Metadata service for the bookshelf-backed Readarr instance (see the long
  # note on services.readarr below). bookshelf falls back to this value when its
  # own MetadataSource setting is empty, so it only takes effect on an instance
  # that has not been given an explicit source in the UI.
  #
  #   https://api.bookinfo.pro         Goodreads-derived, works, keeps an
  #                                    existing Readarr database usable
  #   https://hardcover.bookinfo.pro   Hardcover, better metadata, needs a
  #                                    fresh /var/lib/readarr and a new SeerrNG
  #                                    link
  readarrMetadataUrl = "https://api.bookinfo.pro";
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # AMD OpenCL for tone mapping
    hardware.graphics.extraPackages = lib.mkIf config.device.hardware.mesa.enable [
      pkgs.libva
      pkgs.libva-vdpau-driver
      pkgs.libvdpau-va-gl
      pkgs.rocmPackages.clr.icd
    ];

    # Jellyfin is reachable only through the Caddy reverse proxy (ports 80/443),
    # so no direct firewall port is opened here.
    services.jellyfin.enable = true;

    # Give each service write access only to its own directories on /Vault and
    # make the rest of /Vault read-only, so a compromised app can't touch other
    # users' files. ProtectSystem="full" keeps /var/lib (app config) writable.
    #   - jellyfin:  its own media library
    #   - sonarr/radarr/lidarr/readarr: ingest downloads, import into the library
    #   - bazarr:    subtitles next to library media
    #   - transmission: completed downloads
    #   - kapowarr:  comic library and its own download folder
    #   - shelfmark: its ingest target and its own download folder
    #   - prowlarr/flaresolverr: no /Vault write access
    # Kapowarr (comic books) ships no NixOS module, so its account and unit are
    # defined by hand. It belongs to the shared `users` group like the rest of
    # the stack so it can hand files to/from Transmission and Jellyfin.
    #
    # Parked with the rest of the chain: see device.app.books.
    users.users.kapowarr = lib.mkIf booksEnabled {
      isSystemUser = true;
      group = "users";
      home = "/var/lib/kapowarr";
    };

    # Shelfmark (ebooks) likewise runs under its own account in the shared
    # `users` group; see the serviceConfig override below for why it cannot use
    # the nixpkgs module's default DynamicUser.
    users.users.shelfmark = lib.mkIf booksEnabled {
      isSystemUser = true;
      group = "users";
      home = "/var/lib/shelfmark";
    };

    # The Kavita module creates its own account and group; the account only
    # needs adding to the shared `users` group, because the library tree is
    # 2775 root:users and even a read needs the group bit. It never writes to
    # /Vault (see its serviceConfig below), so that is the whole of its access.
    users.users.kavita.extraGroups = ["users"];

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

    systemd.services = let
      vaultRw = writable: {
        ProtectSystem = lib.mkForce "full";
        ReadOnlyPaths = ["/Vault"];
        ReadWritePaths = writable;
        # Every service here runs in the shared `users` group and they hand
        # files to each other through /Vault/Downloads. The upstream servarr
        # modules pin UMask to 0022, so anything they create is group-read-only
        # and the next service in the chain cannot write to it.
        UMask = lib.mkForce "0002";
      };
    in {
      jellyfin.serviceConfig = vaultRw ["/Vault/Jellyfin"];
      sonarr.serviceConfig = vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"];
      radarr.serviceConfig = vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"];
      lidarr.serviceConfig = vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"];
      readarr.serviceConfig = lib.mkIf booksEnabled (vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"]);
      # The nixpkgs readarr/shelfmark modules instantiate their systemd unit for
      # every systemd.services.<name> key that exists at all, so an mkIf that
      # evaluates to nothing still leaves a start-less readarr.service behind
      # (no ExecStart, nothing wanting it). It is never started either way;
      # `enable = false` makes that policy explicit, so the unit cannot be
      # started even if something later acquires a reference to it. A no-op
      # while the chain is enabled.
      readarr.enable = lib.mkIf (!booksEnabled) false;
      shelfmark.enable = lib.mkIf (!booksEnabled) false;
      bazarr.serviceConfig = vaultRw ["/Vault/Jellyfin" "/Vault/Downloads"];
      transmission.serviceConfig = vaultRw ["/Vault/Downloads"];
      prowlarr.serviceConfig = vaultRw [];
      flaresolverr.serviceConfig = vaultRw [];

      # Kavita reads the library and nothing else: its database, covers and
      # metadata all live in /var/lib/kavita (which ProtectSystem="full" leaves
      # writable), and its "save covers to folder" option is off by default.
      # So it is the one service here that gets NO /Vault write path - the
      # shared 2775 tree plus the `users` group above is enough to scan it.
      # Give it a write path only if you turn that option on.
      kavita.serviceConfig = vaultRw [];

      # seerr is deliberately absent from this list. Its module already sets
      # ProtectSystem="strict", whereas vaultRw force-downgrades that to "full"
      # while adding a /Vault rule it has no use for: Seerr only ever talks to
      # Jellyfin and the *arr APIs over HTTP. Leaving the module's own (strict)
      # setting alone is both simpler and tighter.
      #
      # It does need DynamicUser turned off, though. SeerrNG refuses to use a
      # config path containing a symlink (a symlink-attack guard it adds on top
      # of upstream), and systemd's DynamicUser always publishes StateDirectory
      # as /var/lib/<name> -> /var/lib/private/<name>. A real account makes
      # /var/lib/seerr an ordinary directory, which satisfies the guard.
      seerr.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = lib.mkForce "seerr";
      };

      # Comic book manager, the *arr-shaped hole in the stack. Upstream has no
      # NixOS module, so the unit is written out here. It binds loopback only;
      # Caddy fronts it on kapowarr.lan like everything else.
      # Parked with the rest of the chain: see device.app.books.
      kapowarr = lib.mkIf booksEnabled {
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
          (vaultRw ["/Vault/Downloads" "/Vault/Jellyfin"])
        ];
      };

      # The nixpkgs Shelfmark module runs it under DynamicUser with UMask 0077
      # inside a ProtectSystem="strict" sandbox. Both would break the shared
      # library: a dynamic UID is not a member of the `users` group, and 0077
      # files are unreadable by Jellyfin. Give it a real account in the shared
      # group instead. Note that strict mode makes /Vault read-only, so the
      # library paths below are required rather than optional.
      # Parked with the rest of the chain: see device.app.books.
      shelfmark.serviceConfig = lib.mkIf booksEnabled {
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

      # Attach the transmission systemd service to the VPN namespace.
      transmission.vpnConfinement = {
        enable = true;
        vpnNamespace = "wg0";
      };

      # bookshelf resolves metadata through METADATA_URL only when its own
      # MetadataSource setting is empty, which is the case on a fresh instance.
      # services.readarr already fills the unit's environment from the `settings`
      # option; this is merged on top of it. It MUST be assigned here rather
      # than as a second top-level `systemd.services.<name>...` line: that is
      # the same attribute `systemd.services` twice in one attrset, which Nix
      # rejects with "attribute already defined" before any module merging.
      readarr.environment = lib.mkIf booksEnabled {
        METADATA_URL = readarrMetadataUrl;
      };
    };

    # Kavita signs its auth tokens with a TokenKey secret, so it cannot live in
    # the world-readable Nix store - it belongs in /etc, like the WireGuard
    # config. The module consumes it through LoadCredential, which FAILS the
    # unit when the source file is missing (there is no "-" prefix as there is
    # on EnvironmentFile above), so it is generated once here rather than
    # requiring a hand-made file before the first switch. 64 random bytes are
    # exactly the 512 bits the module option asks for, and the `-s` test keeps
    # the existing key across rebuilds - regenerating it would invalidate every
    # logged-in Kavita session.
    system.activationScripts.kavita-token-key.text = ''
      if [ ! -s /etc/kavita/token.key ]; then
        ${pkgs.coreutils}/bin/install -d -m 0700 /etc/kavita
        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.coreutils}/bin/head -c 64 /dev/urandom | ${pkgs.coreutils}/bin/base64 --wrap=0 > "$tmp"
        ${pkgs.coreutils}/bin/install -m 0600 "$tmp" /etc/kavita/token.key
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
    '';

    # bookshelf is still a .NET 6 application - its global.json pins the SDK and
    # the projects target net6.0 - and .NET 6 is out of support, so nixpkgs
    # marks both the SDK and the ASP.NET runtime as insecure. They are required
    # to build and to run it, and nothing else in this configuration pulls them
    # in, so the permission is granted for exactly these two store paths. If a
    # nixpkgs bump changes their versions, the build error names the new ones.
    #
    # Gated on the books toggle, so a parked stack needs no insecure packages
    # and a nixpkgs bump can no longer break evaluation because of them.
    nixpkgs.config.permittedInsecurePackages = lib.mkIf booksEnabled [
      "dotnet-sdk-6.0.428"
      "aspnetcore-runtime-6.0.36"
    ];

    # Every *arr app points Transmission at its own per-category directory
    # (/Vault/Downloads/radarr, .../tv-sonarr, .../lidarr) and Transmission
    # finishes a torrent by moving it out of .incomplete into that directory.
    # If the directory is not group-writable the move fails with EACCES, the
    # finished data is stranded in .incomplete, and the *arr apps log
    # "path does not exist or is not accessible" forever while the download
    # vanishes from their view. Keep them group-writable with the setgid bit so
    # files created inside keep the shared `users` group.
    systemd.tmpfiles.rules =
      [
        "d /Vault/Downloads 2775 root users -"
        "d /Vault/Downloads/.incomplete 2775 root users -"
        "d /Vault/Downloads/radarr 2775 root users -"
        "d /Vault/Downloads/tv-sonarr 2775 root users -"
        "d /Vault/Downloads/lidarr 2775 root users -"
      ]
      # The parked chain's folders. Kept (rather than deleted) so re-enabling
      # device.app.books comes back to the same layout; on a parked stack they
      # are simply never created.
      ++ lib.optionals booksEnabled [
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

    # Reverse proxy every service on its own subdomain.
    # *.lan is plain HTTP for the local network; only Jellyfin gets a public
    # HTTPS subdomain on *.${publicDomain} for friends.
    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable (lib.listToAttrs (
      (map mkLanVhost activeSites)
      ++ lib.optionals (config.device.security.reverse-proxy.publicDomain != "") (map mkPublicVhost publicSites)
    ));

    networking.hosts = lib.mkMerge [
      {
        "172.67.188.67" = ["1337x.to"];
        "104.21.40.193" = ["1337x.to"];
      }
      (lib.mkIf config.device.security.reverse-proxy.enable {
        "127.0.0.1" = lanHosts;
      })
    ];
    environment.systemPackages = with pkgs; [
      # Server
      jellyfin
      jellyfin-web
      jellyfin-ffmpeg
    ];

    # Automatic downloading
    services = {
      bazarr = {
        enable = true;
        group = "users";
      };
      sonarr = {
        enable = true;
        group = "users";
      };
      radarr = {
        enable = true;
        group = "users";
      };
      lidarr = {
        enable = true;
        group = "users";
      };
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
      # `readarrMetadataUrl` selects the metadata service. The default is the
      # one bookshelf ships with: Goodreads-derived but working, and compatible
      # with an existing Readarr database, so this is a drop-in replacement and
      # the SeerrNG link (URL + API key) keeps working untouched. Pointing it at
      # https://hardcover.bookinfo.pro instead switches the instance to
      # Hardcover, whose metadata is much higher quality - but that mode is NOT
      # backward compatible with a Readarr database, so it also means deleting
      # /var/lib/readarr and re-entering indexers, the Transmission download
      # client, the /Vault/Jellyfin/Books/Books root folder, and the new API key
      # in SeerrNG.
      #
      # In Readarr set: download client = Transmission (via the wg0 namespace
      # address, as in the `sites` entry above), indexers = Prowlarr, and root
      # folder = /Vault/Jellyfin/Books/Books. That root is shared with
      # Shelfmark's INGEST_DIR; both organise as Author/Title so they coexist,
      # but a title fetched by both lands twice - prefer SeerrNG for requested
      # books and Shelfmark's own UI for manga and raw Nyaa releases.
      readarr = lib.mkIf booksEnabled {
        enable = true;
        group = "users";
        package = pkgs.bookshelf;
      };
      # Ebook search/request front end. Ingest goes straight into the existing
      # Jellyfin library tree, organised as Author/Title (Year), so Jellyfin
      # picks new books up on its own.
      shelfmark = lib.mkIf booksEnabled {
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
      # Reading server over the same library tree Jellyfin serves. Jellyfin's
      # book support is a video server's side feature: its EPUB, PDF and comic
      # readers are web-client plugins with no series management, no per-page
      # progress sync and no OPDS feed, and a PDF comic is rasterised
      # client-side by pdf.js on every zoom. Kavita's readers are the point of
      # the product - RTL/manga and webtoon modes, fit modes, reading lists,
      # per-page progress, OPDS for e-readers and KOReader/Mihon sync.
      #
      # It reads the SAME files, so nothing above changes: Jellyfin keeps
      # scanning /Vault/Jellyfin/Books as its Books library and Kapowarr/
      # Shelfmark/Readarr keep writing into it. In Kavita's UI add two
      # libraries after the first start:
      #
      #   comics -> /Vault/Jellyfin/Books          (Hellboy et al., PDFs)
      #   ebooks -> /Vault/Jellyfin/Books/Books    (Shelfmark/Readarr target)
      #
      # Both are Loose-Leaf/Comic or Book libraries respectively; pick "Comic"
      # for the first so Kavita reads the ComicInfo.xml sidecars already sitting
      # next to each PDF. Kavita takes PDFs, but CBZ/EPUB give the better
      # reader, so it is worth converting the PDFs (kcc) and having the ebook
      # side fetch EPUB rather than MOBI/AZW3.
      #
      # LAN-only by convention, exactly like the rest of the stack; add
      # `public = true` to its entry in `sites` above to read from outside the
      # house without Tailscale.
      kavita = {
        enable = true;
        tokenKeyFile = "/etc/kavita/token.key";
        settings = {
          Port = 5000;
          # Caddy fronts it on kavita.lan, so it binds loopback like the rest.
          IpAddresses = "127.0.0.1";
        };
      };
      # Requests front end, served through Caddy too; no direct port opened.
      # SeerrNG is the fork of Seerr that extends the movies/TV request workflow
      # to music, ebooks and audiobooks. It reuses the upstream module - the
      # service honours the same PORT/CONFIG_DIRECTORY contract - so only the
      # binary swaps. stateRevision = 1 selects the current config location
      # (/var/lib/seerr, a real directory) instead of the legacy
      # /var/lib/jellyseerr/config, whose parent is a DynamicUser symlink that
      # SeerrNG's path guard rejects.
      seerr = {
        enable = true;
        package = pkgs.seerrng;
        stateRevision = 1;
      };
      prowlarr.enable = true;

      # Bypass Cloudflare on protected indexers (e.g. 1337x).
      # Point Prowlarr at http://127.0.0.1:8191 as a FlareSolverr proxy.
      flaresolverr.enable = true;
    };

    # VPN namespace for torrenting. The WireGuard config lives at a neutral
    # system path (/etc), not under a particular user's home, so nothing depends
    # on which user owns the flake.
    vpnNamespaces.wg0 = {
      enable = true;
      wireguardConfigFile = "/etc/wireguard/wg0.conf";
      portMappings = [
        {
          from = 9091;
          to = 9091;
        }
      ];
    };

    # Torrenting
    services.transmission = {
      enable = true;
      group = "users";
      package = pkgs.transmission_4;
      settings = {
        download-dir = "/Vault/Downloads";
        incomplete-dir = "/Vault/Downloads/.incomplete";
        incomplete-dir-enabled = true;
        umask = "002";
        rpc-bind-address = "0.0.0.0";
        rpc-whitelist-enabled = false;
        # Stop seeding once a torrent's share ratio hits 0.00 (right after
        # download completes). Uses the kebab-case keys Transmission 4 honors.
        "ratio-limit" = 0;
        "ratio-limit-enabled" = true;
        # Also stop seeding if a torrent is idle for 0 minutes.
        "idle-seeding-limit" = 0;
        "idle-seeding-limit-enabled" = true;
      };
    };
  };
}
