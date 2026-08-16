# User-level Wayland configuration: cursor theme, GTK icon theme.
{
  pkgs,
  ...
}: {
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 16;
  };

  gtk = {
    gtk4.theme = null;
    enable = true;
    # Papirus: colourful icons that stay legible on both light and dark shells,
    # so it keeps working whichever light/dark mode caelestia is in.
    iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };
  };

  # Keep force so the static settings.ini is (re)written cleanly on each switch.
  xdg.configFile."gtk-3.0/settings.ini".force = true;
}
