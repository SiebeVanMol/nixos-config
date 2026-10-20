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
  # Re-colours the borders with `hyprctl eval` instead of `hyprctl reload`: a reload
  # re-applies the cursor theme and drops pointer state, and changing a wallpaper
  # writes a new scheme, so reloading here broke the cursor mid-game. See
  # ./theme-apply.nu for the whole story.
  themeApplyScript = pkgs.writers.writeNuBin "caelestia-theme-apply" (
    lib.replaceStrings
    ["HYPRCTL" "DCONF" "SCHEME"]
    [
      "${pkgs.hyprland}/bin/hyprctl"
      "${pkgs.dconf}/bin/dconf"
      "${config.home.homeDirectory}/.local/state/caelestia/scheme.json"
    ]
    (builtins.readFile ./theme-apply.nu)
  );
in {
  imports = [
    # Caelestia desktop shell (Quickshell-based).
    caelestia-shell.homeManagerModules.default
  ];

  # Two packages caelestia's theming writes settings for but does not install:
  # - the CLI is separate from the shell service, so `caelestia wallpaper -r` and
  #   friends were unavailable in a terminal and to any bind naming them plainly;
  # - `adw-gtk3`, because apply_gtk() runs `dconf write .../gtk-theme 'adw-gtk3-dark'`
  #   and GTK3 apps fall back to the default theme when that name resolves to
  #   nothing. GTK4 apps need no theme package: they read the generated
  #   ~/.config/gtk-4.0/gtk.css and the `color-scheme` preference directly.
  home.packages = [
    config.programs.caelestia.cli.package
    pkgs.adw-gtk3
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

  # The shell leaks. Upstream issue #1927 reports the launcher's app scan taking
  # RSS to ~900 MB within twenty minutes, and one user at 11 GiB after three days
  # of uptime; this host's process has already peaked at 1.5 GiB (437 MB resident
  # at the time of measuring). A daily restart bounds it without capping memory
  # or killing the shell under the user's hands: at 04:00 nothing is on screen,
  # the unit restarts in its own environment, and the shell reconnects to the
  # compositor. Delete this once the pinned version is past the fix - the running
  # shell was 1.0.0 while the flake already pins 2.5.0, so a rebuild may well
  # make this redundant.
  systemd.user.services.caelestia-reload = {
    Unit = {
      Description = "Restart caelestia to bound its memory leak";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${config.systemd.user.systemctlPath} --user restart caelestia.service";
    };
  };

  systemd.user.timers.caelestia-reload = {
    Unit = {Description = "Daily caelestia restart";};
    Timer = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
    };
    Install = {WantedBy = ["timers.target"];};
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
    # Launch terminal apps via foot's client (see ../shell/home/foot.nix).
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
      # Every wallpaper change and every scheme change rewrites scheme.json, and each
      # rewrite starts this oneshot again. With systemd's default limit (5 starts in
      # 10s) a few quick wallpaper changes set the limit, and the *path* unit then
      # fails with "unit-start-limit-hit" and stays dead: the borders - and now the
      # GTK theme - silently stop following caelestia until the session restarts.
      # Disabling the limit is correct here because the unit is idempotent and cheap.
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "oneshot";
      # `lib.getExe`, not the store path itself: writeNuBin produces a *directory*
      # with bin/<name> inside, and pointing ExecStart at the directory fails with
      # status 203/EXEC. That is how this unit had been failing silently on every
      # trigger before it was caught - the path unit kept starting it, it kept
      # dying in 2ms, and nothing ever re-applied the colours.
      ExecStart = lib.getExe themeApplyScript;
    };
  };

  systemd.user.paths.caelestia-theme-apply = {
    Unit = {Description = "Watch caelestia scheme for theme changes";};
    Path = {PathChanged = ["%h/.local/state/caelestia/scheme.json"];};
    Install = {WantedBy = ["graphical-session.target"];};
  };
}
