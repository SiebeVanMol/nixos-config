# Soulseek: slskd, confined to the ProtonVPN namespace.
#
# Peer-to-peer: it announces the host's address to every peer and downloads from
# strangers, so it gets the same wg0 namespace as any download client - no
# traffic or real address leaks if the VPN drops. The namespace itself is in
# vpn.nix, shared with Transmission; this file adds what is specific to slskd.
# The namespace INPUT policy DROPs everything, so two exceptions:
#   * openVPNPorts opens the Soulseek listen port on the tunnel, so peers can
#     reach us - without it slskd downloads but can never be uploaded from.
#   * a port mapping opens the web UI on the veth peer, which is how Caddy
#     reaches it (localhost cannot - locally generated traffic skips PREROUTING).
# ProtonVPN only forwards an inbound port on some servers (NAT-PMP); set
# listenPort below to the port natpmpc reports. It changes per session.
{
  config,
  lib,
  pkgs,
  media,
  ...
}: let
  # Must match the port ProtonVPN forwards; see the note at the top.
  listenPort = 50300;

  # The web UI. Caddy reaches it at the wg0 namespace address.
  webPort = 5030;
in {
  # The music stack has its own toggle; it does not need Jellyfin.
  config = lib.mkIf config.device.app.music.enable {
    services.slskd = {
      enable = true;
      # As with Navidrome, `users` must be the primary group: the module's
      # PrivateUsers=true maps only that group, and the library is 2775
      # root:users.
      group = "users";
      # The Soulseek account and web password are secrets, so they live in
      # /etc, not the world-readable Nix store. Generated below when missing.
      environmentFile = "/etc/slskd/slskd.env";

      settings = {
        # The config file is in the Nix store and has to stay the truth.
        remote_file_management = false;
        flags.force_share_scan = true;

        directories = {
          # slskd downloads into a staging directory, not the library: Lidarr
          # (driven by Soularr) imports from here, so the library stays managed
          # by Lidarr instead of accumulating files it never sees.
          downloads = media.musicDownloads;
          # Incomplete files stay outside both, so neither Lidarr nor a scanner
          # ever sees a half-written track.
          incomplete = media.musicIncomplete;
        };

        # Share the LIBRARY (not the staging directory): what is worth sharing
        # is the finished collection, not the arrivals.
        shares.directories = [media.musicLibrary];
        # Re-scan the share hourly so albums Lidarr has just imported become
        # uploadable without a slskd restart.
        shares.cache.retention = 60;

        soulseek = {
          description = "slskd on nixos-desktop";
          listen_port = listenPort;
        };

        web = {
          port = webPort;
          # Caddy arrives over the veth, so binding loopback only would hide
          # the UI from the host entirely.
          address = "0.0.0.0";
          https.disabled = true;
        };
      };
    };

    systemd.services.slskd = {
      # The point of this file: no traffic escapes except through the tunnel.
      vpnConfinement = {
        enable = true;
        vpnNamespace = "wg0";
      };

      serviceConfig = {
        # The module already pins ProtectSystem="strict"; this narrows the
        # writable part of /Vault to the staging and incomplete directories,
        # and replaces the module's own read-only list (derived from the share,
        # which is not a download target any more so it only needs to be
        # readable). The repo's usual framing: /Vault read-only, the paths
        # beneath it that need writing listed explicitly.
        ReadOnlyPaths = lib.mkForce [media.vault];
        # Files slskd creates are group-writable so Lidarr and Navidrome in the
        # shared `users` group can still read and move them.
        UMask = lib.mkForce "0002";
      };
    };

    # Expose the web UI through the namespace, exactly the way Transmission's
    # RPC is exposed: the mapping's netns INPUT rule is what lets the host
    # connect at all, and Caddy's upstream is the veth address.
    vpnNamespaces.wg0.portMappings = [
      {
        from = webPort;
        to = webPort;
      }
    ];

    # Let peer connections in on the tunnel interface. Without this the
    # namespace's default DROP on INPUT rejects every incoming peer.
    vpnNamespaces.wg0.openVPNPorts = [
      {
        port = listenPort;
        protocol = "both";
      }
    ];

    # slskd's EnvironmentFile has no optional form, so the unit fails outright
    # until the file exists. Generate it once, as Kavita's TokenKey is: a
    # random web password and API key, plus CHANGE_ME placeholders for the
    # Soulseek account, which only its owner can supply. The API key is what
    # Soularr uses to drive slskd; read the web password with
    # `sudo cat /etc/slskd/slskd.env`.
    system.activationScripts.slskd-env.text = ''
      if [ ! -s /etc/slskd/slskd.env ]; then
        ${pkgs.coreutils}/bin/install -d -m 0700 /etc/slskd
        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        {
          echo "SLSKD_SLSK_USERNAME=CHANGE_ME"
          echo "SLSKD_SLSK_PASSWORD=CHANGE_ME"
          echo "SLSKD_USERNAME=admin"
          printf 'SLSKD_PASSWORD=%s\n' \
            "$(${pkgs.coreutils}/bin/head -c 24 /dev/urandom | ${pkgs.coreutils}/bin/base64 --wrap=0)"
          printf 'SLSKD_API_KEY=%s\n' \
            "$(${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64 --wrap=0)"
        } > "$tmp"
        ${pkgs.coreutils}/bin/install -m 0600 "$tmp" /etc/slskd/slskd.env
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi

      # Installs that predate the API key get one appended rather than being
      # asked to redo the Soulseek credentials.
      if ! ${pkgs.gnugrep}/bin/grep -q '^SLSKD_API_KEY=' /etc/slskd/slskd.env; then
        printf 'SLSKD_API_KEY=%s\n' \
          "$(${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64 --wrap=0)" \
          >> /etc/slskd/slskd.env
      fi
    '';

    device.media.services.slskd = {
      port = webPort;
      # The UI lives inside the namespace, so Caddy has to address the
      # namespace's veth peer rather than loopback.
      host = config.vpnNamespaces.wg0.namespaceAddress;
      dashboard = {
        group = "downloads";
        order = 20;
        title = "slskd";
        description = "Soulseek";
      };
      backup.statePaths = ["/etc/slskd"];
      backup.sqliteRoots = ["/var/lib/slskd"];
    };
  };
}
