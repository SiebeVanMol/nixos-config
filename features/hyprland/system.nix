# System-level Hyprland compositor configuration.
# Enables Hyprland with UWSM session management.
{
  config,
  lib,
  ...
}: {
  options.device.wm.hyprland.enable =
    lib.mkEnableOption "the Hyprland compositor with UWSM session management";

  config = lib.mkIf config.device.wm.hyprland.enable {
    programs.hyprland.enable = true;
    programs.hyprland.withUWSM = true;
    programs.hyprland.xwayland.enable = true;
    services.displayManager.generic.environment.XDG_CURRENT_DESKTOP = "X-NIXOS-SYSTEMD-AWARE";
  };
}
