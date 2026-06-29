{ pkgs, ... }:
{
  home.packages = with pkgs; [
    #########
    # Utils #
    #########
      # Archives
      p7zip
      # File System
      dust
      ripgrep
      pipe-rename
      # Monitoring
      yazi
      nvtopPackages.amd
      # Web
      curl
      # Extra
      tokei
      tealdeer

    ###############
    # Programming #
    ###############
      # Compilers
      gcc
      gnumake
      cmake
      valgrind
      rustup
      python3
      mypy
      # Cargo
      cargo-expand
      cargo-tarpaulin
      cargo-flamegraph
      cargo-all-features
      # code tools
      man-pages
      norminette
      lmstudio
      opencode
      rocmPackages.rocm-smi
      # Git
      jujutsu

    #########  
    # Games #
    #########
      # Launcher
      xivlauncher
      prismlauncher
      heroic
      # Modding
      openmw

    ################
    # Productivity #
    ################
      # Communication
      vesktop
      # File sharing
      qbittorrent
      # Proton
      proton-pass
      protonmail-desktop

    #########
    # Media #
    #########
      # Music
      ncspot
      # Jellyfin
      jellyfin-desktop

      jetbrains.clion
      jetbrains.pycharm
      jetbrains.rust-rover
  ];

  home.sessionVariables = {
    OBS_VKCAPTURE = 1;
    PROTON_FSR4_UPGRADE = 1;
    # PROTON_ENABLE_WAYLAND = 1;
    # PROTON_ENABLE_HDR = 1;
  };

  services.jellyfin-mpv-shim = {
    enable = true;
    mpvConfig = {
      target-colorspace-hint = "yes";
      vo = "dmabuf-wayland";
    };
  };
  
  programs = {
    btop = {
      enable = true;
      package = pkgs.btop-rocm;
      
      settings = {
        theme_background = false;
        update_ms = 100;
        check_temp = true;
        show_cpu_freq = true;
      };
    };

    fastfetch = {
      enable = true;
      settings.modules = [
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

    obs-studio = {
      enable = true;

      plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        obs-multi-rtmp
        obs-pipewire-audio-capture
        obs-vkcapture
      ];
    };

    anki = {
      enable = true;
      addons = with pkgs.ankiAddons; [
        review-heatmap
        passfail2
      ];
    };
  };
}
