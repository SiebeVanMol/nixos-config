# Features that span the machine and the user.
#
# A feature is one directory with both halves of something that exists on both
# sides: `system.nix` is the NixOS configuration, `home.nix` the Home Manager
# one. They live here rather than in `system/` and `users/` so that "where is
# hermes configured" has one answer - and so the two halves cannot drift, which
# is what happened while they sat three directories apart.
#
# The machine half is imported here, for every host: the feature's own toggle or
# option decides whether it does anything. The user half is imported where it
# belongs - by the user who runs it (`users/<name>/home.nix`) for something
# personal, or by `home/core.nix` for something every user has, like the shell -
# so a feature one person uses never lands in another person's home.
#
# A feature earns a directory here only by spanning both sides, and the test is
# "one fact, one place" rather than size: `device.shell.program` is one line of
# machine configuration, and it is here because the account's shell, the Home
# Manager configuration for it and the terminal that launches it all have to name
# the same program. Something that is only system- or only user-side stays where
# it is, which is most of the tree: `system/app/steam.nix` and
# `home/caelestia.nix` are not features by this definition.
#
# `checks.x86_64-linux.features` holds the rule to it: a directory here must have
# both halves and its machine half must be imported below.
{
  imports = [
    ./shell/system.nix
    ./hyprland/system.nix
  ];
}
