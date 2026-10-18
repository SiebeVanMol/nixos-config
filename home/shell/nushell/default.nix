# Nushell configuration: disable banner, set shorthand aliases.
#
# Carapace is deliberately absent. Its `_carapace nushell` output is still the
# pre-0.116 `{|spans| ...}` external completer, which nushell 0.116 parses with
# `Positional completer input deprecated` on the first completion of every
# session, and keeping it working means carrying a rewritten copy of that
# bridge in this repository - a copy to keep in step with carapace releases for
# completions only one shell uses. Nothing else relied on it (the bash
# integration was never enabled), so the package is gone rather than patched.
# Revisit if carapace starts emitting the record-style completer, or if
# external-command flag completion is missed enough to pay for the copy.
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
}
