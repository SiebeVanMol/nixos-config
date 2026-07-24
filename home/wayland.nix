# User-level Wayland configuration: wallpaper rotation script, cursor theme, GTK icon theme.
{
  pkgs,
  ...
}: {
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    AWWW_TRANSITION = "none";
  };
  services.awww.enable = true;

  home.packages = with pkgs; [
    (
      writers.writeNuBin "swww_randomize" /*nu*/''
          # Pick a random wallpaper from `dir` every `time` interval.
          # Skips the update whenever any window is fullscreen.
          def main [dir: path, time: duration] {
            loop {
              if (hyprctl clients -j | from json | get fullscreen | all {$in == 0}) {
                let file = (select_file $dir)
                apply_theme ($file.name | get 0)
              }
              sleep $time
            }
          }

          # Pick a random image file from a directory tree.
          def select_file [dir: path] {
            let files = ls ($"($dir)/**/*" | into glob) | where type == file
            let index = random int ..($files | length)
            $files | select $index
          }

          # Generate wallust colours, set wallpaper, update Hyprland borders and reload Waybar.
          def apply_theme [img: path] {
            [
              (${wallust}/bin/wallust run $img --quiet -s | ignore),
              (${imagemagick}/bin/magick $img -gravity center -extent 1.005:1 ~/.cache/rofi.bmp),
              (${awww}/bin/awww img $img),
            ] | par-each { $in }
            set_hyprland_border_colors
            pkill waybar -SIGUSR2 | ignore
          }

          # Read the current wallust accent colours and apply them as a
          # two-stop gradient (color1 → color5) to Hyprland's active window
          # border.  The inactive border is kept at a translucent white.
          def set_hyprland_border_colors [] {
            try {
              let c1 = (open ~/.cache/wallust/hypr-colors | lines | where ($it =~ "color1") | first | parse "color1 = \"{c}\"" | get c.0)
              let c5 = (open ~/.cache/wallust/hypr-colors | lines | where ($it =~ "color5") | first | parse "color5 = \"{c}\"" | get c.0)
              let v1 = ("\"" + "rgb(" + $c1 + ")" + "\"")
              let v2 = ("\"" + "rgb(" + $c5 + ")" + "\"")
              let cmd = ("hl.config({ general = { col = { active_border = { colors = {" + $v1 + ", " + $v2 + "} }, inactive_border = \"rgba(ffffffbb)\" } } })")
              hyprctl eval $cmd | ignore
            }
          }
        ''
      )
  ];

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 16;
  };

  gtk = {
    gtk4.theme = null;
    enable = true;
    iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };
  };
}
