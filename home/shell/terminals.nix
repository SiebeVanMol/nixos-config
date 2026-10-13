# Foot terminal: Nushell as the shell, Fira Code Nerd Font Mono.
#
# foot runs in server mode: `foot --server` is a systemd user service and every
# window is a `footclient` connecting to it, so one process owns the Wayland
# connection, font cache and rendering threads. The server is pulled in with the
# graphical session.
#
# Colouring is left to foot's built-in palette: in server mode the palette lives
# in the server process, so a runtime theme would mean rewriting foot.ini and
# signalling the daemon on every scheme change.
{
  pkgs,
  lib,
  ...
}: let
  # The Nerd Font variant carries the glyphs (plain Fira Code does not);
  # fontconfig reports its family with the spaces removed.
  font = "FiraCode Nerd Font Mono:size=11";

  # foot launches the shell from the server process, whose environment is the
  # session's rather than the user profile's, so `nu` is referenced by absolute
  # path instead of relying on PATH.
  nushell = lib.getExe pkgs.nushell;

  # Terminal apps (btop, yazi, ...) are launched by caelestia via $TERMINAL.
  # This is a foot *client*: every window still goes through the server, and its
  # app-id is "footclient" (see app-id below), which window rules match on.
  footclient = lib.getExe' pkgs.foot "footclient";
in {
  home.sessionVariables = {
    TERM = "foot";
    TERMINAL = footclient;
  };

  programs.foot = {
    enable = true;

    server = {
      enable = true;
      # uwsm (enabled in system/wm/hyprland.nix) brings up
      # graphical-session.target; the server is pulled in with it.
      systemdTarget = "graphical-session.target";
    };

    settings = {
      main = {
        inherit font;
        shell = nushell;
        # Start nu as a login shell, so it picks up the session environment
        # (and its own login.nu) the way the desktop expects.
        login-shell = "yes";
        app-id = "footclient";
      };

      # 75% opacity, matching the rest of the desktop. `alpha-mode=matching`
      # keeps the window opaque when the compositor cannot blend, so text stays
      # readable rather than every cell being 25% transparent.
      colors-dark = {
        alpha = "0.75";
        alpha-mode = "matching";
      };

      scrollback = {
        lines = 10000;
      };

      mouse = {
        hide-when-typing = "yes";
      };
    };
  };
}
