# Alex's user home. The Japanese input stack lives in the shared
# home/input-method.nix, which home/core.nix imports for every user.
{...}: {
  imports = [
    ../../home/core.nix

    ./editor.nix
    ./browser.nix
    ./programs.nix
  ];
}
