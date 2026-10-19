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
# personal like hermes, or by `home/core.nix` for something every user has, like
# the shell - so a feature one person uses never lands in another person's home.
#
# A feature earns a directory here only by spanning both sides. Something that
# is only system- or only user-side stays where it is: `system/app/steam.nix`
# and `home/hyprland.nix` are not features by this definition.
{
  imports = [
    ./hermes/system.nix
    ./shell/system.nix
  ];
}
