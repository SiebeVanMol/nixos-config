# Nushell configuration: disable banner, set shorthand aliases, enable Carapace completions.
{
  programs.nushell = {
    enable = true;

    settings = {
      show_banner = false;
    };
    shellAliases = {
      clr = "clear";
      fetch = "fastfetch";
    };
  };

  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };
}
