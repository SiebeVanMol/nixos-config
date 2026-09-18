# Snowy's user home: MIME application defaults, Japanese input (fcitx5 + Mozc).
{pkgs, ...}: {
  imports = [
    ../../home/core.nix

    ./editor.nix
    ./neovim.nix
    ./browser.nix
    ./programs.nix
  ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Terminal
      "x-scheme-handler/terminal" = "kitty.desktop";

      # Browser
      "application/pdf" = "zen-beta.desktop";
      "x-scheme-handler/http" = "zen-beta.desktop";
      "x-scheme-handler/https" = "zen-beta.desktop";
      "x-scheme-handler/about" = "zen-beta.desktop";
      "x-scheme-handler/unknown" = "zen-beta.desktop";

      # Game mod manager protocol handlers. The generated mimeapps.list is
      # read-only (managed by home-manager), so Amethyst can't register these
      # itself; without them Nexus's "Mod Manager Download" (nxm://) and
      # Thunderstore's ror2mm:// buttons do nothing. They route to the
      # dedicated .desktop entries below, which run the app through the
      # `amethyst-mod-manager` launcher so $APPDIR is set.
      "x-scheme-handler/nxm" = "amethyst-nxm.desktop";
      "x-scheme-handler/ror2mm" = "amethyst-ror2mm.desktop";

      # Files
      "inode/directory" = "yazi.desktop";

      # Images
      "image/png" = "yazi.desktop";
      "image/jpeg" = "yazi.desktop";
      "image/gif" = "yazi.desktop";
      "image/webp" = "yazi.desktop";
      "image/svg+xml" = "yazi.desktop";
      "image/tiff" = "yazi.desktop";
      "image/bmp" = "yazi.desktop";

      # Text
      "text/plain" = "Helix.desktop";
      "text/html" = "Helix.desktop";
      "text/markdown" = "Helix.desktop";
      "text/csv" = "Helix.desktop";
      "text/xml" = "Helix.desktop";
    };
  };

  # Protocol handlers for Amethyst's nxm:// and ror2mm:// one-click installs.
  # Run through the launcher (not the app's bare bin/python3) so $APPDIR is set
  # and the vendored _vendor loads - see overlays/amethyst-mod-manager.nix.
  xdg.desktopEntries = {
    amethyst-nxm = {
      name = "Amethyst Mod Manager (NXM Handler)";
      exec = "amethyst-mod-manager --nxm %u";
      mimeType = ["x-scheme-handler/nxm"];
      noDisplay = true;
      terminal = false;
    };
    amethyst-ror2mm = {
      name = "Amethyst Mod Manager (Thunderstore Handler)";
      exec = "amethyst-mod-manager --ror2mm %u";
      mimeType = ["x-scheme-handler/ror2mm"];
      noDisplay = true;
      terminal = false;
    };
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        fcitx5-mozc
        fcitx5-gtk
      ];
    };
  };
}
