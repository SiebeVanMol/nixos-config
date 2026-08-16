# Kitty terminal configuration: Nushell as default shell, Fira Code font, 75% opacity.
# The theme colors live in a separate colors.conf (included below) that caelestia
# rewrites when the theme changes, so new kitty windows always inherit the palette.
{
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
}
