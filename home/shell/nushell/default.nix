# Nushell configuration: disable banner, set shorthand aliases.
#
# No external completer, on purpose. Carapace is the usual choice and it is out
# because nixpkgs ships 1.7.3, whose `_carapace nushell` output is the
# pre-0.116 `{|spans| ...}` completer that nushell 0.116 warns about on the
# first completion of every session; fish is out because completing from it
# costs a process per Tab for something nushell already covers for its own
# commands, paths, variables and environment. What is left is nushell's built-in
# completion: nu commands and their flags, files and directories, variables and
# env vars. External commands get no flag or subcommand completion, which is the
# known cost.
#
# If that cost ever bites, carapace-bin 1.8.1 emits `{|place| ...}` with a compat
# shim and was run against nushell 0.116.1 here without a warning, so
# `programs.carapace.enableNushellIntegration = true` on a newer nixpkgs is the
# one-line route back; the fish bridge is the other, as a closure in
# `extraConfig` plus `pkgs.fish` in `home.packages`.
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
