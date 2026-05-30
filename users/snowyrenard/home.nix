{ pkgs, ... }: {
  imports = [
    ../../home/core.nix

    ./editor.nix
    ./browser.nix
    ./programs.nix
  ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Terminal
      "x-scheme-handler/terminal" = "footclient.desktop";
      
      # Browser
      "application/pdf"           = "zen-beta.desktop";
      "x-scheme-handler/http"     = "zen-beta.desktop";
      "x-scheme-handler/https"    = "zen-beta.desktop";
      "x-scheme-handler/about"    = "zen-beta.desktop";
      "x-scheme-handler/unknown"  = "zen-beta.desktop";

      # Files
      "inode/directory" = "yazi.desktop";

      # Images
      "image/png"      = "yazi.desktop";
      "image/jpeg"     = "yazi.desktop";
      "image/gif"      = "yazi.desktop";
      "image/webp"     = "yazi.desktop";
      "image/svg+xml"  = "yazi.desktop";
      "image/tiff"     = "yazi.desktop";
      "image/bmp"      = "yazi.desktop";

      # Text
      "text/plain"    = "Helix.desktop";
      "text/html"     = "Helix.desktop";
      "text/markdown" = "Helix.desktop";
      "text/csv"      = "Helix.desktop";
      "text/xml"      = "Helix.desktop";
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
