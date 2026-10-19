# Snowy's wallpaper keys. The two collections the old swww_randomize binds used,
# on the same keys so muscle memory still works: SUPER+ALT+1 for everything under
# ~/Pictures/Backgrounds (Art included - `caelestia wallpaper -r` recurses) and
# SUPER+ALT+9 for the Cosplay collection, which lives outside that tree, hence the
# ~/ path instead of a subfolder name.
{...}: {
  device.wallpaper.binds = [
    {
      key = "SUPER + ALT + 1";
      folder = "";
    }
    {
      key = "SUPER + ALT + 9";
      folder = "~/Pictures/Extra/Cosplay";
    }
  ];
}
