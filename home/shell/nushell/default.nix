# Nushell configuration: disable banner, set shorthand aliases, and hand
# completions to fish.
#
# Completions live in `fish.nu`, which drives fish's completion engine from
# nushell's external-completer hook. Only fish's binary is wanted, so it is a
# package here rather than `programs.fish.enable`, which would also configure
# fish as a login shell with its own config and completion directories.
#
# Carapace stays out. nixpkgs ships 1.7.3, whose `_carapace nushell` output is
# the pre-0.116 `{|spans| ...}` completer that nushell 0.116 warns about on the
# first completion of every session. Carapace-bin 1.8.1 fixes that, and todo.md
# says what to do when nixpkgs catches up; until then fish's engine is the one
# that both works and is declarative end to end.
{pkgs, ...}: {
  programs.nushell = {
    enable = true;

    settings = {
      show_banner = false;
    };
    shellAliases = {
      clr = "clear";
      fetch = "fastfetch";
    };

    extraConfig = ''
      source ${./fish.nu}
    '';
  };

  # The completer in `fish.nu` shells out to `fish --command`, so the binary has
  # to be on PATH.
  home.packages = [pkgs.fish];
}
