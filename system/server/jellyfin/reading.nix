# Kavita: the reading server, over the same library tree Jellyfin serves.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stack = import ./layout.nix {inherit config lib;};
in {
  config = lib.mkIf stack.enabled {
    # The Kavita module creates its own account and group; the account only
    # needs adding to the shared `users` group, because the library tree is
    # 2775 root:users and even a read needs the group bit. It never writes to
    # /Vault (see its serviceConfig below), so that is the whole of its access.
    users.users.kavita.extraGroups = ["users"];

    # Reading server over the same library tree Jellyfin serves. Jellyfin's
    # book support is a video server's side feature: its EPUB, PDF and comic
    # readers are web-client plugins with no series management, no per-page
    # progress sync and no OPDS feed, and a PDF comic is rasterised client-side
    # by pdf.js on every zoom. Kavita's readers are the point of the product -
    # RTL/manga and webtoon modes, fit modes, reading lists, per-page progress,
    # OPDS for e-readers and KOReader/Mihon sync.
    #
    # It reads the SAME files, so nothing else changes: Jellyfin keeps scanning
    # /Vault/Jellyfin/Books as its Books library. Nothing writes new books into
    # that tree any more (the acquisition chain was removed - see default.nix),
    # so in Kavita's UI add two libraries after the first start:
    #
    #   comics -> /Vault/Jellyfin/Books          (Hellboy et al., PDFs)
    #   ebooks -> /Vault/Jellyfin/Books/Books    (the ebook tree)
    #
    # Both are Loose-Leaf/Comic or Book libraries respectively; pick "Comic" for
    # the first so Kavita reads the ComicInfo.xml sidecars already sitting next
    # to each PDF. Kavita takes PDFs, but CBZ/EPUB give the better reader, so it
    # is worth converting the PDFs (kcc) and having the ebook side fetch EPUB
    # rather than MOBI/AZW3.
    #
    # LAN-only by convention, exactly like the rest of the stack; add
    # `public = true` to its entry in layout.nix to read from outside the house
    # without Tailscale.
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
    systemd.services.kavita.serviceConfig = stack.vaultRw [];

    # Kavita signs its auth tokens with a TokenKey secret, so it cannot live in
    # the world-readable Nix store - it belongs in /etc, like the WireGuard
    # config. The module consumes it through LoadCredential, which FAILS the
    # unit when the source file is missing (there is no "-" prefix as there is
    # on EnvironmentFile elsewhere), so it is generated once here rather than
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
  };
}
