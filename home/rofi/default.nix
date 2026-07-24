# Rofi application launcher with custom theme and config directory.
{
  programs.rofi = {
    enable = true;
    font = "Fira Code Mono 10";
    theme = ./configs/config.rasi;
  };

  home.file.".config/rofi" = {
    source = ./configs;
    recursive = true;
  };
}
