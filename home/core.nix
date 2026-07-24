# Home Manager core module imported by every user.
# Sets home directory, state version, and pulls in shared desktop (shell, WM, bar, launcher, theme).
{ username, ... }: {
  home = {
    inherit username;
    homeDirectory = "/home/${username}";

    stateVersion = "25.05";
  };

  imports = [
    ./shell

    ./hyprland.nix
    ./rofi
    ./waybar
    ./wallust
  ];

  programs.home-manager.enable = true;
}
