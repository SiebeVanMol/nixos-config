# Foot terminal configuration: client/server mode, Nushell as default shell, Fira Code font, 75% opacity.
{
  home.sessionVariables = {
    TERM = "footclient";
    TERMINAL = "footclient";
  };

  programs.foot = {
    enable = true;
    server.enable = true;

    settings = {
      main = {
        shell = "nu";

        font = "Fira Code Nerd Font Mono:size=11";
        dpi-aware = "yes";
      };

      colors-dark = {
        alpha = 0.75;
      };
    };
  };

  xdg.desktopEntries = {
    foot = {
      name = "foot";
      noDisplay = true;
    };
    footclient = {
      name = "footclient";
      noDisplay = true;
    };
    foot-server = {
      name = "foot-server";
      noDisplay = true;
    };
  };
}
