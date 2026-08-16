# Kitty terminal configuration: Nushell as default shell, Fira Code font, 75% opacity.
# The theme colors live in a separate colors.conf (included below) that caelestia
# rewrites when the theme changes, so new kitty windows always inherit the palette.
{ lib, ... }: {
  home.sessionVariables = {
    TERM = "xterm-kitty";
    TERMINAL = "kitty";
  };

  programs.kitty = {
    enable = true;

    settings = {
      font_family = "Fira Code Nerd Font Mono";
      font_size = 11;
      background_opacity = "0.75";
      shell = "nu";
      allow_remote_control = "yes";
      disable_ligatures = "cursor";
    };

    extraConfig = ''
      include ~/.config/kitty/colors.conf
    '';
  };

  # kitty auto-reloads kitty.conf; make it a writable file so caelestia can
  # `touch` it after updating colors.conf, triggering a live reload of all windows.
  xdg.configFile."kitty/kitty.conf".force = true;

  home.activation.makeKittyConfWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    INI="$HOME/.config/kitty/kitty.conf"
    if [ -L "$INI" ]; then
      cp -L "$INI" "$INI.tmp" && rm -f "$INI" && mv "$INI.tmp" "$INI"
    fi
    chmod u+w "$INI"
  '';
}
