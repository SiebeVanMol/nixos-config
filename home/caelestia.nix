# Caelestia desktop shell (Quickshell-based), its theme integration, and the
# wallpaper rotation unit. Everything shell-specific lives here so core.nix stays
# a generic base that every user imports regardless of which shell they run.
#
# Seed caelestia's theme settings into its runtime config, and push the palette
# into kitty (the terminal) so all kitty windows inherit it.
#
# Caelestia OWNS ~/.config/caelestia/shell.json (it writes to it to persist
# settings), so home-manager must NOT manage that file as a read-only symlink.
# The kitty palette is applied by a systemd path unit that watches scheme.json
# and regenerates colors.conf + repaints kitty (new windows read it via the
# include), not via a postHook in shell.json.
{
  config,
  pkgs,
  lib,
  caelestia-shell,
  ...
}: let
  kittyColorsPy = ''
    import json, sys
    scheme, out = sys.argv[1], sys.argv[2]
    d = json.load(open(scheme))
    c = d.get('colours', {})
    def hx(k, default='000000'):
        v = c.get(k)
        return '#' + v if v else '#' + default
    def term(i):
        v = c.get('term%d' % i)
        return '#' + v if v else '#000000'
    L = ['background ' + hx('background'), 'foreground ' + hx('onBackground')]
    for i in range(16):
        L.append('color%d %s' % (i, term(i)))
    open(out, 'w').write('\n'.join(L) + '\n')
  '';

  themeApplyScript = pkgs.writeShellScript "caelestia-theme-apply" ''
        SCHEME="$HOME/.local/state/caelestia/scheme.json"
        COLORS="$HOME/.config/kitty/colors.conf"
        if [ -f "$SCHEME" ]; then
          mkdir -p "$HOME/.config/kitty"
          ${pkgs.python3}/bin/python3 - "$SCHEME" "$COLORS" <<'PY'
    ${kittyColorsPy}
    PY
          # kitty auto-reloads kitty.conf on change; touch it so it re-reads colors.conf
          # and repaints all running (and future) windows.
          touch "$HOME/.config/kitty/kitty.conf" 2>/dev/null || true
        fi
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
        # Keep the shell's UI consistently Japanese.
        "LC_ALL=ja_JP.UTF-8"
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
    # The top-level "theme" block is no longer a recognised option for this
    # caelestia version (it emits `Unknown option "theme"`), and the theme is
    # applied by the caelestia-theme-apply service watching scheme.json, so it
    # is intentionally not seeded here.
    # Launch terminal apps (btop, etc.) with kitty instead of the default foot.
    d.setdefault('general', {}).setdefault('apps', {})['terminal'] = ['kitty']
    # Disable the idle lock: the auto-lock fired mid-game (idle isn't reset by
    # gamepad input). The entry stays but is marked disabled so the config stays
    # valid for caelestia (an empty "timeouts" list is an illegal value). hypridle
    # is removed too, so nothing dims or powers off the display on idle.
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

  # Write the initial kitty palette so terminals are themed before the first apply.
  home.activation.writeKittyColors = lib.hm.dag.entryAfter ["writeBoundary"] ''
        SCHEME="$HOME/.local/state/caelestia/scheme.json"
        if [ -f "$SCHEME" ]; then
          mkdir -p "$HOME/.config/kitty"
          ${pkgs.python3}/bin/python3 - "$SCHEME" "$HOME/.config/kitty/colors.conf" <<'PY'
    ${kittyColorsPy}
    PY
        fi
  '';

  # Reliably re-apply the theme (kitty colors + hyprland borders) whenever
  # caelestia writes a new scheme, regardless of caelestia's own postHook.
  systemd.user.services.caelestia-theme-apply = {
    Unit = {
      Description = "Apply caelestia theme to kitty and hyprland";
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
