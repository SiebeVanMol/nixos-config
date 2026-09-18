{
  config,
  lib,
}: let
  # What counts as "inside" for the guard on the LAN vhosts below: the local
  # network and the Tailscale mesh.
  internalNetworks = import ../../../lib/internal-networks.nix {inherit lib;};
in rec {
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
  # Transmission, FlareSolverr, Kavita) is a
  # sensitive admin/management UI and stays LAN/Tailscale-only. That last part is
  # no longer a matter of discipline: `public` is the only thing that produces a
  # vhost reachable from the internet, and mkLanVhost below refuses clients that
  # are not on the local network or the Tailscale mesh.
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
      name = "kavita";
      port = 5000;
    }
  ];

  # Every service in `sites` runs: there is no parked half of the stack any
  # more, so this is just the table under its published name.
  activeSites = sites;

  publicSites = lib.filter (s: s ? public && s.public) activeSites;

  # Where a vhost sends its traffic. Everything is on the loopback except
  # Transmission, which answers inside the WireGuard namespace (see the note on
  # its entry in `sites`).
  upstream = site: "${site.host or "127.0.0.1"}:${toString site.port}";

  # Public vhosts: a plain reverse proxy, with automatic HTTPS via the HTTP-01
  # challenge.
  mkPublicVhost = site: {
    name = "${site.name}.${config.device.security.reverse-proxy.publicDomain}";
    value.extraConfig = "reverse_proxy ${upstream site}";
  };

  # LAN vhosts: the same proxy, but only for clients that are really inside.
  #
  # Ports 80 and 443 are forwarded from the internet - that is how the public
  # vhosts obtain their certificates - and Caddy chooses a vhost from the Host
  # header alone. Unprotected, `curl -H 'Host: flaresolverr.lan' http://<public
  # ip>/v1` from anywhere in the world reached FlareSolverr, which obligingly
  # fetched and returned whatever URL it was handed, and the same trick reached
  # every *arr admin UI. The remote_ip matcher below keeps all *.lan vhosts to
  # the local network and the Tailscale mesh; anything else is refused before it
  # reaches a service.
  mkLanVhost = site: {
    name = "http://${site.name}.lan";
    value.extraConfig = ''
      @internal remote_ip ${lib.concatStringsSep " " internalNetworks.all}
      handle @internal {
        reverse_proxy ${upstream site}
      }
      handle {
        respond "This service is only reachable from the local network." 403
      }
    '';
  };

  # Derived from `sites` rather than listed again: one place to add a service,
  # and a parked service cannot leave a stale *.lan name behind.
  lanHosts = map (s: s.name + ".lan") activeSites;

  # Give each service write access only to its own directories on /Vault and
  # make the rest of /Vault read-only, so a compromised app can't touch other
  # users' files. ProtectSystem="full" keeps /var/lib (app config) writable.
  #   - jellyfin:  its own media library
  #   - sonarr/radarr/lidarr: ingest downloads, import into the library
  #   - bazarr:    subtitles next to library media
  #   - transmission: completed downloads
  #   - kavita:    its own reading-server state
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
