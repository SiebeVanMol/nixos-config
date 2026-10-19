# The user half of the shell feature: the configured shell, the shell-agnostic
# tools, and the terminal.
#
# Which shell and which terminal are options, not edits: `device.shell.program`
# is declared in the system.nix beside this file (the account's shell and this
# configuration must name the same program, so it is one option read through
# `osConfig`), and `device.shell.terminal` is declared here because the terminal
# is entirely a Home Manager thing - its server is a user unit.
#
# The two tables are what make that choice cheap. A shell is *selectable* in
# ../shells.nix, which says which package answers the name; a shell is
# *configured* here, which says which directory shapes it. Those are separate on
# purpose: zsh or fish with no configuration is a legitimate choice that runs
# upstream's defaults. The terminal table is the option's enum, so adding kitty is
# a kitty.nix plus one line here.
#
# Every table member is imported unconditionally and gates itself with `mkIf` on
# the option (`nushell/default.nix`, `foot.nix`). Importing only the selected one
# would read an option - `osConfig` here, `config` there - inside `imports`,
# which the module system evaluates before options have values: that is an
# infinite recursion, not a style preference.
{
  config,
  lib,
  ...
}: let
  shellConfigs = {
    nushell = ./nushell;
  };

  terminalConfigs = {
    foot = ./foot.nix;
  };
in {
  options.device.shell.terminal = lib.mkOption {
    type = lib.types.enum (builtins.attrNames terminalConfigs);
    default = "foot";
    description = ''
      Terminal the desktop launches through $TERMINAL, and whose configuration
      Home Manager owns. Adding one means adding its file to `terminalConfigs`
      above - the option follows the table.
    '';
  };

  imports =
    [
      ./common.nix
      ./starship.nix
    ]
    ++ lib.attrValues shellConfigs
    ++ lib.attrValues terminalConfigs;

  # bash stays on whatever the login shell is: shell scripts, `system()` and an
  # editor's fallback shell all expect a POSIX shell to exist, and enabling it
  # costs a package nobody has to start.
  config.programs.bash.enable = true;
}
