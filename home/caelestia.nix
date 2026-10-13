# Caelestia desktop shell (Quickshell-based), its theme integration, and the
# wallpaper rotation unit. Everything shell-specific lives here so core.nix stays
# a generic base every user imports.
#
# Seeds caelestia's runtime settings and re-applies the desktop theme (Hyprland
# borders, via caelestia's own scheme/current.lua) whenever caelestia writes a
# new scheme. The terminal is NOT themed from here: foot runs in server mode and
# keeps its own palette. Caelestia OWNS ~/.config/caelestia/shell.json, so
# home-manager must not manage it as a read-only symlink.
{
  config,
  pkgs,
  lib,
  caelestia-shell,
  ...
}: let
  themeApplyScript = pkgs.writeShellScript "caelestia-theme-apply" ''
    ${pkgs.hyprland}/bin/hyprctl reload || true
  '';
in {
  imports = [
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
        "CAELESTIA_WALLPAPERS_DIR=${config.home.homeDirectory}/Pictures/Backgrounds"
        "QT_QPA_PLATFORMTHEME=gtk3"
      ];
    };
  };

  # Auto-rotate the wallpaper on a timer, like the old swww_randomize loop.
  systemd.user.services.caelestia-wallpaper = {
    Unit = {
      Description = "Rotate caelestia wallpaper";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${config.programs.caelestia.cli.package}/bin/caelestia wallpaper -r";
      Environment = ["CAELESTIA_WALLPAPERS_DIR=${config.home.homeDirectory}/Pictures/Backgrounds"];
    };
    Install = {WantedBy = ["graphical-session.target"];};
  };

  home.activation.seedCaelestiaTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "$HOME/.config/caelestia"
        ${pkgs.python3}/bin/python3 - "$HOME/.config/caelestia/shell.json" <<'PY'
    import json, os, sys
    p = sys.argv[1]
    d = {}
    if os.path.exists(p) or os.path.islink(p):
        try:
            with open(p) as f:
                d = json.load(f)
        except Exception:
            d = {}
    # The top-level "theme" block is no longer recognised by this caelestia
    # version (it emits `Unknown option "theme"`); the theme is applied by the
    # caelestia-theme-apply service watching scheme.json instead.
    # Launch terminal apps via foot's client (see ./shell/terminals.nix).
    d.setdefault('general', {}).setdefault('apps', {})['terminal'] = ['${lib.getExe' pkgs.foot "footclient"}']
    # Idle lock disabled: the auto-lock fired mid-game (gamepad input does not
    # reset idle). The entry stays but disabled, because an empty "timeouts" list
    # is illegal. hypridle is removed too.
    d.setdefault('general', {}).setdefault('idle', {})['timeouts'] = [
        {"enabled": False, "timeout": 120, "idleAction": "lock"},
    ]
    # Drop any home-manager store symlink so caelestia can write to a real file.
    if os.path.islink(p) or os.path.exists(p):
        os.remove(p)
    with open(p, 'w') as f:
        json.dump(d, f, indent=4)
    PY
  '';

  # Re-apply Hyprland's borders whenever caelestia writes a new scheme,
  # regardless of caelestia's own postHook.
  systemd.user.services.caelestia-theme-apply = {
    Unit = {
      Description = "Apply caelestia theme to hyprland";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = themeApplyScript;
    };
  };

  systemd.user.paths.caelestia-theme-apply = {
    Unit = {Description = "Watch caelestia scheme for theme changes";};
    Path = {PathChanged = ["%h/.local/state/caelestia/scheme.json"];};
    Install = {WantedBy = ["graphical-session.target"];};
  };
}
