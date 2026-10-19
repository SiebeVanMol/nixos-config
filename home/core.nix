# Home Manager core module imported by every user. Sets the home state version
# and pulls in the two features every user gets (shell, session) plus the
# shared single-sided settings (input method, desktop apps).
#
# `home.username`/`home.homeDirectory` are intentionally NOT set: as a NixOS
# submodule Home Manager derives them from users.users.<name>, so each user's
# config points at its own home even on a host with several users.
{...}: {
  home = {
    stateVersion = "25.05";
  };

  imports = [
    ../features/shell/home

    ../features/hyprland/home.nix

    ./input-method.nix
    ./desktop-apps.nix
  ];

  programs.home-manager.enable = true;
}
