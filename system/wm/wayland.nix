{
  imports = [
    ./fonts.nix
  ];

  services.displayManager = {
    enable = true;
    ly.enable = true;
  };
}
