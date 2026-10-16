# Display manager: ly (TUI login manager). The shared font configuration in
# ./fonts.nix arrives through system/default.nix's `importDir ./wm`, which takes
# every .nix in this directory, so it is not imported a second time here.
{...}: {
  services.displayManager = {
    enable = true;
    ly.enable = true;
  };
}
