# Waybar status bar: workspaces, window title, battery, audio, network, clock, and system tray.
{ pkgs, ... }:
{
  programs.waybar = {
    enable = true;

    systemd = {
      enable = true;
      targets = [ "graphical-session.target" ];
    };

    settings = [{
      layer = "top";

      margin-top = 5;
      margin-bottom = -5;
      margin-left = 10;
      margin-right = 10;
      spacing = 0;

      modules-left = [
        "hyprland/workspaces"
      ];
      modules-center = [
        "hyprland/window"
      ];
      modules-right = [
        "battery"
        "pulseaudio"
        "network"
        "clock"
        "tray"
      ];

      "hyprland/workspaces" = {
        on-click = "activate";
        active-only = false;
        all-outputs = true;
        formats = "{id}";
        max-length = 1;
      };
      "hyprland/window" = {
        max-length = 200;
        separate-outputs = true;
      };

      tray = {
        spacing = 10;
      };

      clock = {
        format-alt = "{:%m月%d日}";
        tooltip = false;
      };

      backlight = {
        format = "{icon}";
        format-icons = [ "" "" "" "" "" "" "" "" "" ];
        tooltip-format = "{percent}%";
      };

      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon}";
        format-charging = "{capacity}% 󱐋";
        format-plugged = "{capacity}% ";
        format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
        tooltip-format = "{capacity}%";
      };

      network = {
        format-wifi =  "";
        format-ethernet =  "";
        format-disconnected =  "";
        tooltip-format-wifi =  "{essid}";
        on-click =  "${pkgs.foot}/bin/footclient nmtui";
      };

      pulseaudio = {
        format = "{icon}";
        format-bluetooth = "{icon} {format_source}";
        format-icons = { default = [ "" "" "" ]; };
        tooltip-format = "{volume}%";
        on-click = "${pkgs.foot}/bin/footclient ${pkgs.wiremix}/bin/wiremix";
      };
    }];

    style = ./style.css;
  };
}
