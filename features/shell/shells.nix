# The shells this feature can put an account into, by the name the option takes.
#
# One table rather than a `programs` attrset per half: the system half picks the
# account's shell from it and the terminal's config picks the binary foot
# launches from it, and those two must be the same program or the session starts
# a shell the account does not have.
#
# A name here is a shell that can be *selected*; whether Home Manager also
# configures it is a separate table (features/shell/home/default.nix), because a
# shell with no configuration is a legitimate choice - it runs its defaults.
{pkgs}: {
  nushell = pkgs.nushell;
  bash = pkgs.bashInteractive;
  zsh = pkgs.zsh;
  fish = pkgs.fish;
}
