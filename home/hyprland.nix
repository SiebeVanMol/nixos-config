{
  pkgs,
  config,
  ...
}: {
  imports = [ ./wayland.nix ];

  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false;
    package = null;

    configType = "lua";

    # App settings
    extraConfig = /*lua*/ ''
      local terminal = os.getenv("TERMINAL")
      local browser = os.getenv("BROWSER")
      local drun = "rofi -show drun"

      --require("${config.xdg.cacheHome}/wallust/hypr-colors")

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
      })

      -------------------
      -- LOOK AND FEEL --
      -------------------
      hl.env("XCURSOR_SIZE", 16)
      hl.env("HYPRCURSOR_SIZE", 16)

      hl.on("hyprland.start", function()
        hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 16")
        hl.exec_cmd("sleep 5s; swww_randomize ~/Pictures/Backgrounds/Art/ 309sec")
      end)
    
      hl.config({
        general ={
          gaps_in = 5,
          gaps_out = 10,

          border_size = 3,

          layout = "dwindle",
        },

        decoration = {
          rounding = 10,
          col = {
            --active_border = rgb(color10),
            --inactive_border = rgba(ffffffbb),
          },

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

      local closeWindow = hl.bind(mod .. " + SHIFT + Q", hl.dsp.window.close())
      hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))

      hl.bind(mod .. " + N", hl.dsp.window.float({ action = "toggle" }))
      -- hl.bind(mod .. " + V", hl.dsp.layout(togglesplit))

      hl.bind(mod .. " + F",         hl.dsp.window.fullscreen({ "maximized", toggle }))
      hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ "fullscreen", toggle }))

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
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";       # avoid starting multiple hyprlock instances.
        before_sleep_cmd = "loginctl lock-session";    # lock before suspend.
        after_sleep_cmd = "hyprctl dispatch dpms on";  # to avoid having to press a key twice to turn on the display.
      };
      listener = [
        {
            timeout = 90;#sec
            # ddcci is for external monitor support.
            on-timeout = "${pkgs.brillo}/bin/brillo -el -O && ${pkgs.brillo}/bin/brillo -el -S 10%";         # set monitor backlight to minimum, avoid 0 on OLED monitor.
            on-resume = "${pkgs.brillo}/bin/brillo -el -I";                 # monitor backlight restore.
        }
        
        # { 
        #     timeout = 90;#sec
        #     on-timeout = "${pkgs.brightnessctl}/bin/brightnessctl -sd *:kbd_backlight set 0"; # turn off keyboard backlight.
        #     on-resume = "${pkgs.brightnessctl}/bin/brightnessctl -rd *:kbd_backlight";        # turn on keyboard backlight.
        # }
        
        # {
        #     timeout = 60;# 1min
        #     on-timeout = "loginctl lock-session";            # lock screen when timeout has passed
        # }
        
        {
            timeout = 300;# 5min
            on-timeout = "hyprctl dispatch dpms off";                            # screen off when timeout has passed
            on-resume = "hyprctl dispatch dpms on && ${pkgs.brillo}/bin/brillo -el -I";          # screen on when activity is detected after timeout has fired.
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
}
