{
  config,
  lib,
}: rec {
  # Everything the media stack shares: which services exist, how they are
  # reached, and the hardening helper every one of them uses. This is a plain
  # function rather than a module so each part of the stack can pull in exactly
  # what it needs with `import ./layout.nix {inherit config lib;}` - the values
  # below depend only on options defined elsewhere (device.app.*,
  # device.security.*), never on what the stack's own modules set, so there is
  # no evaluation cycle to worry about.

  # The single toggle the whole stack hangs off.
  enabled = config.device.app.jellyfin.enable;

  # Services exposed through the reverse proxy: name → local port.
  # `public = true` additionally publishes the service on *.${publicDomain}.
  # Keep ONLY Jellyfin and Seerr public; every other entry here (the *arr suite,
  # Transmission, FlareSolverr, Kapowarr, Shelfmark, Kavita) is a
  # sensitive admin/management UI and stays LAN/Tailscale-only.
  sites = [
    # The dashboard is the landing page for the whole stack: one place to look
    # instead of remembering a dozen *.lan names. It is declared as a site like
    # anything else, and configured in dashboard.nix.
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
  # note in books.nix). bookshelf falls back to this value when its own
  # MetadataSource setting is empty, so it only takes effect on an instance that
  # has not been given an explicit source in the UI.
  #
  #   https://api.bookinfo.pro         Goodreads-derived, works, keeps an
  #                                    existing Readarr database usable
  #   https://hardcover.bookinfo.pro   Hardcover, better metadata, needs a
  #                                    fresh /var/lib/readarr and a new SeerrNG
  #                                    link
  readarrMetadataUrl = "https://api.bookinfo.pro";

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
  vaultRw = writable: {
    ProtectSystem = lib.mkForce "full";
    ReadOnlyPaths = ["/Vault"];
    ReadWritePaths = writable;
    # Every service here runs in the shared `users` group and they hand files
    # to each other through /Vault/Downloads. The upstream servarr modules pin
    # UMask to 0022, so anything they create is group-read-only and the next
    # service in the chain cannot write to it.
    UMask = lib.mkForce "0002";
  };
}
