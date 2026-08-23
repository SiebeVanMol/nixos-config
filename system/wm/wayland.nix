# Display manager: ly (TUI login manager) and shared font configuration.
{...}: {
  imports = [
    ./fonts.nix
  ];

  services.displayManager = {
    enable = true;
    ly.enable = true;
  };
}
