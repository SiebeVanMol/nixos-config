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

  home.sessionVariables = {
    OBS_VKCAPTURE = 1;
    # FSR4_UPGRADE = 1; # proton-ge overwrite fsr3 to fsr4
  };

  programs = {
    fastfetch = {
      enable = true;
      settings = {
        modules = [
          "title"
          "separator"
          "os"
          "host"
          "kernel"
          "uptime"
          "packages"
          "shell"
          "wm"
          "cpu"
          "gpu"
          "memory"
          "swap"
          "disk"
          "break"
          "colors"
        ];
      };
    };

    mangohud = {
      enable = true;
      enableSessionWide = true;

      settings = {
        no_display = true;
        preset = 3;
        full = true;
      };
    };

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
