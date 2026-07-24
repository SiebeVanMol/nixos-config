# System-level Hyprland compositor configuration.
# Enables Hyprland with UWSM session management, pulls in Wayland display manager and PipeWire audio.
{ ... }:

{
  imports = [
    ./wayland.nix
    ./pipewire.nix
  ];

  programs.hyprland.enable = true;
  programs.hyprland.withUWSM = true;
  services.displayManager.generic.environment.XDG_CURRENT_DESKTOP = "X-NIXOS-SYSTEMD-AWARE";
}
