# Kavita: the reading server, over the same library tree Jellyfin serves.
{
  config,
  lib,
  pkgs,
  media,
  ...
}: {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # The Kavita module creates its own account and group; the account only
    # needs adding to the shared `users` group, because the library tree is
    # 2775 root:users and even a read needs the group bit. It never writes to
    # /Vault (see its serviceConfig below), so that is the whole of its access.
    users.users.kavita.extraGroups = ["users"];

    # Reading server over the same library tree Jellyfin serves. Jellyfin's book
    # support is a video server's side feature; Kavita has RTL/manga and webtoon
    # modes, reading lists, per-page progress, OPDS and KOReader/Mihon sync.
    #
    # It reads the same files, so nothing else changes. Add two libraries after
    # the first start (nothing writes new books any more - the acquisition chain
    # was removed, see default.nix):
    #   comics -> /Vault/Media/Books        (pick "Comic" for ComicInfo.xml)
    #   ebooks -> /Vault/Media/Books/Books
    # CBZ/EPUB give a better reader than PDF, so converting is worthwhile.
    # LAN-only like the rest of the stack; add `public = true` to go wider.
    services.kavita = {
      enable = true;
      tokenKeyFile = "/etc/kavita/token.key";
      settings = {
        Port = 5000;
        # Caddy fronts it on kavita.lan, so it binds loopback like the rest.
        IpAddresses = "127.0.0.1";
      };
    };

    # Kavita reads the library and nothing else: its database, covers and
    # metadata all live in /var/lib/kavita (which ProtectSystem="full" leaves
    # writable), and its "save covers to folder" option is off by default. So it
    # is the one service here that gets NO /Vault write path - the shared 2775
    # tree plus the `users` group above is enough to scan it. Give it a write
    # path only if you turn that option on.
    systemd.services.kavita.serviceConfig = media.vaultRw [];

    # Kavita's TokenKey cannot live in the world-readable store, so it is
    # generated once here (the `-s` test keeps it across rebuilds - regenerating
    # would invalidate every session) and consumed via LoadCredential, which
    # fails the unit if the file is missing.
    system.activationScripts.kavita-token-key.text = ''
      if [ ! -s /etc/kavita/token.key ]; then
        ${pkgs.coreutils}/bin/install -d -m 0700 /etc/kavita
        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.coreutils}/bin/head -c 64 /dev/urandom | ${pkgs.coreutils}/bin/base64 --wrap=0 > "$tmp"
        ${pkgs.coreutils}/bin/install -m 0600 "$tmp" /etc/kavita/token.key
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
    '';

    device.media.services.kavita = {
      port = 5000;
      dashboard = {
        group = "library";
        order = 40;
        title = "Kavita";
        description = "Read";
        icon = "kavita.png";
      };
      backup = {
        sqliteRoots = ["/var/lib/kavita"];
        statePaths = ["/var/lib/kavita/config/appsettings.json"];
      };
    };
  };
}
