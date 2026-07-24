{
  imports = [
    ./nushell

    ./common.nix
    ./starship.nix
    ./terminals.nix
  ];

  # Allow home-manager to take control over bash.
  programs.bash.enable = true;
}
