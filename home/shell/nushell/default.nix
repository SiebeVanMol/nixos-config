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

    # Carapace's own nushell integration is left off on purpose: it sources what
    # `carapace _carapace nushell` prints, which is still the pre-0.116
    # `{|spans| ...}` closure and warns `Positional completer input deprecated`
    # on the first completion of every session. `carapace.nu` is that bridge
    # declared against the record nushell 0.116 passes instead; its header says
    # what was dropped, and todo.md says when it can go.
    extraConfig = ''
      source ${./carapace.nu}
    '';
  };

  programs.carapace = {
    enable = true;
    enableNushellIntegration = false;
  };
}
