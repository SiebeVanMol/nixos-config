# Home Manager core module imported by every user. Sets the home state version
# and pulls in the shared desktop (shell, WM, wallpapers, caelestia).
#
# `home.username`/`home.homeDirectory` are intentionally NOT set: as a NixOS
# submodule Home Manager derives them from users.users.<name>, so each user's
# config points at its own home even on a host with several users.
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
