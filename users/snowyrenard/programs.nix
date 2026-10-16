# Snowy's installed programs: dev tools, games, media, productivity apps.
{pkgs, ...}: {
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
    # Python
    (python3.withPackages (ps: [ps.mypy ps.flake8]))
    # Cargo
    cargo-expand
    cargo-tarpaulin
    cargo-flamegraph
    cargo-all-features
    # Code tools
    man-pages
    norminette

    #########
    # Games #
    #########
    # Launcher
    xivlauncher
    heroic
    prismlauncher
    protonup-qt
    lutris
    amethyst-mod-manager
    rpcs3
    shadps4
    shadps4-qtlauncher

    ################
    # Productivity #
    ################
    # Communication
    discord
    # File sharing
    qbittorrent

    #########
    # Media #
    #########
    # Music
    ncspot

    jetbrains.clion
    jetbrains.pycharm
    jetbrains.rust-rover
    jetbrains.rider
    mono
    godot-mono
  ];

  home.sessionVariables = {
    PROTON_FSR4_UPGRADE = 1;
    # PROTON_USE_OPTISCALER = 1;
    # PROTON_DISCORD_BRIDGE = 1;
    # PROTON_VKD3D_LOWLATENCY = 1;
  };

  # direnv + nix-direnv: loads a project's `use flake` dev shell (from its
  # `.envrc`) into the shell and IDE (e.g. RustRover), caching the environment
  # between runs. Requires nushell integration (see home/shell/nushell).
  programs.direnv = {
    enable = true;
    enableNushellIntegration = true;
    nix-direnv.enable = true;
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
        update_ms = 1000;
        check_temp = true;
        show_cpu_freq = true;
      };
    };

    # fastfetch and mangohud are identical for both users: home/desktop-apps.nix.

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

    dsh = {
      enable = true;
      # Declare the web profile so the module materializes it as "nix-web".
      profiles.web = {
        bundles =
          (with pkgs.dsh.bundles; [
            base
            web-app
          ])
          # @neptune810/dsh-model-router (overlays/dsh-model-router.nix) varies the
          # DeepSeek thinking level per step and can hold a model pool. Its own
          # cordis.patch.yml inserts the `model-router` row, so nothing is declared
          # here for it.
          ++ [pkgs.dsh-model-router];

        # `mode = "managed"`, so every activation restores cordis.patch.yml and
        # anything the Settings UI writes at runtime is lost: the rows that matter
        # (welcome notice, default model) are therefore declared here.
        patch = [
          {
            id = "ui-settings-general";
            name = "@deepseek-ai/dsh-client-ui-settings-general";
            config.welcomeNoticeVersion = "2026-09-28.1";
          }
          {
            id = "agent-default-model";
            name = "@deepseek-ai/dsh-agent-default-model";
            config = {
              provider = "deepseek-official";
              model = "deepseek-flash";
              reasoningEffort = "high";
            };
          }
        ];
      };
    };
  };

  services.dsh = {
    enable = true;
    # No explicit `package`: the module default composes the served profile's
    # bundles (including the third-party one above) into the unit's dsh. Pinning
    # `pkgs.dsh.dsh` here would bypass that composition and the plugin would be
    # in the profile's package.json but absent from the running server.
  };
}
