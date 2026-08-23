# Home Manager core module imported by every user.
# Sets home directory, state version, and pulls in shared desktop (WM, launcher, theme).
# The caelestia shell and its integration live in ./caelestia.nix.
{
  username,
  config,
  ...
}: {
  home = {
    inherit username;
    homeDirectory = "/home/${username}";

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
