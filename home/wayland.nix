{
  pkgs,
  ...
}: {
  home.sessionVariables.NIXOS_OZONE_WL = "1";

  home.sessionVariables = {
    AWWW_TRANSITION = "none";
  };
  services.awww.enable = true;

  home.packages = with pkgs; [
    (
      writers.writeNuBin "swww_randomize" /*nu*/''
          # This script will randomly go through the files of a directory, setting it
          # up as the wallpaper at regular intervals
          def main [dir: path, time: duration] {
            loop {
              if (hyprctl clients -j | from json | get fullscreen | all {$in == 0}) {
                let file = (select_file $dir)

                update_colors ($file.name | get 0)
              }

              sleep $time
            }
          }

          # Select a random file within a directory
          def select_file [dir: path] {
            let input_dir = ($"($dir)/**/*" | into glob) # glob is required to format because magic?
            let files = ls $input_dir | where type == file # Get all the eligible files
            let index = random int ..($files | length) # Select a random number
            $files | select $index # Return the actual file
          }

          # Update the environment based upon the path to an image
          def update_colors [img: path] {
            [
              (${wallust}/bin/wallust run $img --quiet -s | ignore; pkill waybar -SIGUSR2 | ignore),
              (${imagemagick}/bin/magick $img -gravity center -extent 1.005:1 ~/.cache/rofi.bmp),
              (${awww}/bin/awww img $img),
            ] | par-each { $in }
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
