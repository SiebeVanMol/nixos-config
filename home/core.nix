# Home Manager core module imported by every user.
# Sets home state version and pulls in shared desktop (WM, launcher, theme).
# The caelestia shell and its integration live in ./caelestia.nix.
#
# `home.username`/`home.homeDirectory` are intentionally NOT set here: when Home
# Manager is used as a NixOS submodule it derives them from the OS user account
# (`users.users.<name>`) per user, so each user's config automatically points at
# its own home directory even when a host has multiple users.
{...}: {
  home = {
    stateVersion = "25.05";
  };

  imports = [
    ./shell

    ./hyprland.nix
    ./wallpapers.nix
    ./caelestia.nix
  ];

  programs.home-manager.enable = true;
}
