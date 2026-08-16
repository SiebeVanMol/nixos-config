# Home Manager core module imported by every user.
# Sets home directory, state version, and pulls in shared desktop (shell, WM, launcher, theme).
{ username, config, caelestia-shell, ... }: {
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

    # Caelestia desktop shell (Quickshell-based).
    caelestia-shell.homeManagerModules.default
  ];

  programs.caelestia = {
    enable = true;
    systemd = {
      # UWSM launches the shell via the graphical session target, like the old waybar.
      target = "graphical-session.target";
      # Caelestia's FileSystemModel doesn't follow symlinks, so point it straight
      # at the real wallpaper folder instead of relying on ~/Pictures/Wallpapers.
      # QT_QPA_PLATFORMTHEME=gtk3 makes quickshell read the GTK icon theme (Papirus).
      environment = [
        "CAELESTIA_WALLPAPERS_DIR=/home/${username}/Pictures/Backgrounds"
        "QT_QPA_PLATFORMTHEME=gtk3"
      ];
    };
  };

  # Auto-rotate the wallpaper on a timer, like the old swww_randomize loop.
  systemd.user.services.caelestia-wallpaper = {
    Unit = {
      Description = "Rotate caelestia wallpaper";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${config.programs.caelestia.cli.package}/bin/caelestia wallpaper -r";
      Environment = [ "CAELESTIA_WALLPAPERS_DIR=/home/${username}/Pictures/Backgrounds" ];
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  systemd.user.timers.caelestia-wallpaper = {
    Unit = { Description = "Rotate caelestia wallpaper every 5 minutes"; };
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "caelestia-wallpaper.service";
    };
    Install = { WantedBy = [ "timers.target" ]; };
  };

  programs.home-manager.enable = true;
}
