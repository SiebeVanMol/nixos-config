# Alex's installed programs: monitoring, games, git, study tools.
{pkgs, ...}: {
  home.packages = with pkgs; [
    # Archives
    p7zip

    # Monitoring
    btop-rocm
    nvtopPackages.amd

    # Git
    gitui

    # Web Tools
    curl

    # Games
    discord
    gamemode
    xivlauncher
    prismlauncher

    kdePackages.dolphin

    # Study
    anki

    keymapp
  ];

  programs = {
    # fastfetch and mangohud are shared with Snowy: home/desktop-apps.nix.

    git = {
      enable = true;
      settings.user = {
        name = "Snowy Renard";
        email = "snowyrenard@gmail.com";
      };
    };

    gh = {
      enable = true;
      gitCredentialHelper.enable = true;
    };
  };
}
