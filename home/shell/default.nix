# Aggregates shell environment: Nushell, zoxide, Starship prompt, and Foot terminal.
{
  imports = [
    ./nushell
    ./common.nix
    ./starship.nix
    ./terminals.nix
  ];

  programs.bash.enable = true;
}
