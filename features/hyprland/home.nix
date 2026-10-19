# User-level Hyprland configuration: keybindings, animations, hyprlock, xdg-desktop-portal.
#
# Everything here is the shared default; a user changes their own copy of it from
# users/<name>/, which is why the wallpaper keys are an option instead of a
# literal (device.wallpaper.binds).
{
  pkgs,
  lib,
  config,
  ...
}: {
  # The session's own pieces, kept beside the bindings they belong to: the
  # Wayland/GTK environment (wayland.nix), the Quickshell desktop shell and its
  # theme integration (caelestia.nix), and the wallpaper symlink that exists
  # because caelestia's FileSystemModel does not follow one (wallpapers.nix).
  imports = [
    ./wayland.nix
    ./caelestia.nix
    ./wallpapers.nix
  ];

  # One key per wallpaper source, so each user decides their own keys and their
  # own folders. This lives in the home module and not in a host's `device`
  # block because it is a user preference, not a machine feature: every user
  # gets these defaults, and `users/<name>/<file>.nix` overrides them:
  #
  #   device.wallpaper.binds = [
  #     { key = "SUPER + ALT + W"; folder = ""; }        # the whole tree
  #     { key = "SUPER + ALT + 2"; folder = "Cosplay"; } # a subfolder
  #   ];
  #
  # An empty list means no wallpaper keys at all.
  options.device.wallpaper.binds = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        key = lib.mkOption {
          type = lib.types.str;
          example = "SUPER + ALT + W";
          description = "Hyprland key combination, modifiers written out in full.";
        };
        folder = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "Art";
          description = ''
            Where to pick from. Relative names are subfolders of
            ~/Pictures/Backgrounds, and an absolute or ~/ path is used as given.
            Empty means the whole tree.
          '';
        };
      };
    });
    default = [
      {
        key = "SUPER + ALT + W";
        folder = "";
      }
      {
        key = "SUPER + ALT + 1";
        folder = "Art";
      }
    ];
    # Rendered one line per entry into the Lua config below. That rendering uses a
    # plain one-line string with its eight spaces written out, because an indented
    # Nix string would have its leading spaces stripped and drop the generated
    # lines to column 0.
    description = "Keys that change the wallpaper, one per source folder.";
  };

  # The module declares options now, so every setting has to sit under `config`.
  config = {
    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = false;
      package = null;

      configType = "lua";

      # App settings
      extraConfig =
        /*
        lua
        */
        ''
                  local browser = os.getenv("BROWSER")
                  -- $TERMINAL is baked in when Hyprland starts, and home-manager only
                  -- updates the session environment on the *next* login (hm-session-vars.sh
                  -- is read by PAM). A switch that changes the terminal therefore left the
                  -- running session pointing at the old binary: the keybind exec'd the bare
                  -- name and died with "command not found" (kitty, after foot replaced it).
                  -- The keybind now re-reads the freshly generated value at launch time and
                  -- falls back to footclient's store path if even that is missing.
                  -- $TERMINAL is a foot *client*, so the window still goes through the
                  -- foot server (see ../shell/home/foot.nix).
                  local terminal = "sh -c 'TERMINAL=''${TERMINAL:-${lib.getExe' pkgs.foot "footclient"}}; exec $TERMINAL'"
                  -- Caelestia's launcher ("run menu") replaces rofi.
                  local drun = "${config.programs.caelestia.cli.package}/bin/caelestia shell drawers toggle launcher"

                  hl.config({
                    dwindle = {
                      preserve_split = true,
                    }
                  })

                  -------------
                  -- MONITOR --
                  -------------
                  hl.monitor({
                    output = "",
                    mode = "highrr",
                    scale = 1,
                    bitdepth = 10,
                  })

                  -------------------
                  -- LOOK AND FEEL --
                  -------------------
                  hl.env("XCURSOR_SIZE", 16)
                  hl.env("HYPRCURSOR_SIZE", 16)
                  -- `caelestia wallpaper -r [DIR]` reads this at import time; without it a
                  -- terminal or bind falls back to ~/Pictures/Wallpapers, the symlink
                  -- caelestia's FileSystemModel refuses to follow. home.sessionVariables does
                  -- not reach a UWSM session, so it is set here, where binds inherit it.
                  hl.env("CAELESTIA_WALLPAPERS_DIR", os.getenv("HOME") .. "/Pictures/Backgrounds")

                  -- Caelestia writes its colour scheme (and Hyprland border colours) to
                  -- ~/.config/hypr/scheme/current.lua; source it and let background.lua override.
                  local ok, scheme = pcall(dofile, os.getenv("HOME") .. "/.config/hypr/scheme/current.lua")
                  pcall(dofile, os.getenv("HOME") .. "/Pictures/Backgrounds/background.lua")

                  local c1 = color1 or (ok and scheme.primary) or "ff3333"
                  local c2 = color5 or (ok and scheme.tertiary) or (ok and scheme.primary) or "ff00ff"

                  hl.on("hyprland.start", function()
                    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 16")
                  end)

                  hl.config({
                    -- Hyprland reloads itself whenever its config files change, and a reload
                    -- re-applies the cursor theme and drops pointer state for every surface,
                    -- which leaves the cursor broken in a running game. Caelestia rewrites
                    -- ~/.config/hypr/scheme/current.lua on every wallpaper change, so the
                    -- reload used to arrive exactly when a new picture was picked.
                    -- With this off, config changes land on an explicit `hyprctl reload`;
                    -- that is the price of a cursor that survives the session.
                    misc = {
                      disable_autoreload = true,
                    },
                    general = {
                      gaps_in = 5,
                      gaps_out = 10,

                      border_size = 3,

                      layout = "dwindle",

                      col = {
                        active_border = { colors = {"rgb(" .. c1 .. ")", "rgb(" .. c2 .. ")"} },
                        inactive_border = "rgba(ffffffbb)",
                      },
                    },

                    decoration = {
                      rounding = 10,

                      shadow = {
                        enabled = true,
                        range = 4,
                        render_power = 3,
                        color = 0xee1a1a1a,
                      },

                      blur = {
                        enabled = true,
                        size = 2,
                        passes = 1,
                      },
                    },

                    animations = {
                      enabled = true,
                    },
                  })

                  -- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
                  hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
                  hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
                  hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
                  hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
                  hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

                  -- Default springs
                  hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

                  hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
                  hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
                  hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
                  hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
                  hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
                  hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
                  hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
                  hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
                  hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
                  hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
                  hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
                  hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
                  hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
                  hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
                  hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
                  hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
                  hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

                  -----------
                  -- INPUT --
                  -----------
                  hl.config({
                    input = {
                      follow_mouse = 2,
                    },
                  })

                  local mod = "SUPER"

                  hl.bind(mod .. " + W", hl.dsp.exec_cmd(browser))
                  hl.bind(mod .. " + D", hl.dsp.exec_cmd(drun))
                  hl.bind(mod .. " + T", hl.dsp.exec_cmd(terminal))
                  hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))

                  hl.bind(mod .. " + SHIFT + Q", hl.dsp.window.close())
                  hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))

                  hl.bind(mod .. " + N", hl.dsp.window.float({ action = "toggle" }))

                  hl.bind(mod .. " + F",         hl.dsp.window.fullscreen({ "maximized", true }))
                  hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ "fullscreen", true }))

                  -- Wallpapers, on command, one key per entry of device.wallpaper.binds
                  -- (see the option at the top of this module). `caelestia wallpaper -r DIR`
                  -- picks at random from DIR, recursively, and re-derives the colour scheme;
                  -- the launcher's `>wallpaper` entry shows one folder as a grid.
                  local home = os.getenv("HOME")
                  local wallpapers = home .. "/Pictures/Backgrounds"
                  local function wallpaper_dir(folder)
                    if folder == "" then return wallpapers end
                    if folder:sub(1, 1) == "/" then return folder end
                    if folder:sub(1, 2) == "~/" then return home .. folder:sub(2) end
                    return wallpapers .. "/" .. folder
                  end
          ${lib.concatMapStringsSep "\n" (
              bind: "        hl.bind(\"${bind.key}\", hl.dsp.exec_cmd(\"caelestia wallpaper -r \" .. wallpaper_dir(\"${bind.folder}\")))"
            )
            config.device.wallpaper.binds}
                  hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
                  hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
                  hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
                  hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

                  hl.bind(mod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
                  hl.bind(mod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
                  hl.bind(mod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
                  hl.bind(mod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

                  for i = 1, 9 do
                    hl.bind(mod .. " + " .. i, hl.dsp.focus({ workspace = i }))
                    hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
                  end
                  -- Workspace 10 on SUPER+0
                  hl.bind(mod .. " + 0", hl.dsp.focus({ workspace = 10 }))
                  hl.bind(mod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

                  hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
                  hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

                  hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
                  hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

                  ----------------
                  -- WORKSPACES --
                  ----------------
                  hl.window_rule({
                    -- Fix some dragging issues with XWayland
                    name  = "fix-xwayland-drags",
                    match = {
                      class      = "^$",
                      title      = "^$",
                      xwayland   = true,
                      float      = true,
                      fullscreen = false,
                      pin        = false,
                    },

                    no_focus = true,
                  })
        '';
    };

    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          hide_cursor = true;
        };

        background = [
          {
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
          }
        ];

        input-field = [
          {
            size = "200, 50";
            position = "0, -80";
            monitor = "";
            dots_center = true;
            fade_on_empty = false;
            font_color = "rgb(202, 211, 245)";
            inner_color = "rgb(91, 96, 120)";
            outer_color = "rgb(24, 25, 38)";
            outline_thickness = 5;
            shadow_passes = 2;
          }
        ];
      };
    };
    xdg.portal = {
      enable = true;

      config = {
        hyprland.default = ["hyprland" "gtk"];
      };

      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };
  };
}
