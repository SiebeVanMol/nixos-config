# The machine half of the shell feature: which shell an account gets.
#
# This was a bare `shell = pkgs.nushell` in system/default.nix, a directory away
# from the Home Manager configuration that shaped the same program - the straddle
# AGENTS.md used to have to explain. Both halves are here now, and the choice is
# one option instead of two edits: `device.shell.program`.
#
# The option is data the Home Manager half reads through `osConfig`, the same way
# the shell's own home module reads the program. That is deliberate: the value
# has to be identical on both sides, and two options with the same meaning is how
# they end up disagreeing.
#
# Nothing here installs the shell for the *user*: NixOS sets the account's shell,
# and `users.users.*.shell` is what /etc/shells lists, so `chsh` already agrees
# with the session without a second `environment.shells` entry.
{
  config,
  lib,
  pkgs,
  usernames,
  ...
}: let
  cfg = config.device.shell;
  shells = import ./shells.nix {inherit pkgs;};
in {
  options.device.shell.program = lib.mkOption {
    type = lib.types.enum (builtins.attrNames shells);
    default = "nushell";
    description = ''
      Shell every account on the host logs into. The Home Manager half
      (features/shell/home) configures the same shell, and the terminal launches
      it, so choosing here changes all three.
    '';
  };

  config.users.users = lib.genAttrs usernames (_: {
    shell = shells.${cfg.program};
  });
}
