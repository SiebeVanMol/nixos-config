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
    (python3.withPackages (ps: [ps.mypy ps.flake8 ps.huggingface-hub]))
    # Cargo
    cargo-expand
    cargo-tarpaulin
    cargo-flamegraph
    cargo-all-features
    # code tools
    man-pages
    norminette
    llama-cpp-vulkan

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
    PROTON_USE_OPTISCALER = 1;
    PROTON_DISCORD_BRIDGE = 1;
    PROTON_VKD3D_LOWLATENCY = 1;
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

    dsh = {
      enable = true;
      # Declare the web profile so the module materializes it as "nix-web".
      profiles.web = {
        bundles = with pkgs.dsh.bundles; [
          base
          web-app
        ];

        # This profile is `mode = "managed"`, so every activation restores
        # cordis.patch.yml from here and anything the Settings UI writes to it
        # at runtime is lost on the next switch. The rows that matter are
        # therefore declared: the welcome notice, the default model, and the
        # local hipfire route.
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
          {
            # hipfire's `serve` is OpenAI-compatible on loopback, but pi-ai has
            # no catalog entry for it, so the route declares protocol, endpoint
            # and model list by hand. The tag has to match what hipfire reports
            # from GET /v1/models.
            id = "llm-pi-ai";
            name = "@deepseek-ai/dsh-llm-pi-ai";
            config.providers.hipfire = {
              displayName = "hipfire (local)";
              api = "openai-completions";
              baseURL = "http://127.0.0.1:11435/v1";
              # hipfire has no authentication, but a hand-declared route always
              # wires pi-ai's harness API-key auth, so a non-empty value has to
              # resolve. It comes from the unit environment below rather than
              # the credential store, so no secret-shaped file is written.
              apiKeyEnv = "HIPFIRE_API_KEY";
              # One route, four local models with different roles. Each
              # contextWindow matches the per-model memory.max_seq on the host,
              # so the harness never sends more than the daemon reserved for.
              models = [
                {
                  id = "qwen3.8:27b";
                  name = "qwen3.8:27b (128k, quality - slow)";
                  contextWindow = 131072;
                }
                {
                  id = "qwen3.6:27b-mq3";
                  name = "qwen3.6:27b-mq3 (64k, coding)";
                  contextWindow = 65536;
                }
                {
                  id = "qwen3.5:9b";
                  name = "qwen3.5:9b (128k, fast)";
                  contextWindow = 131072;
                }
                {
                  id = "qwen3.5:4b";
                  name = "qwen3.5:4b (128k, fastest)";
                  contextWindow = 131072;
                }
              ];
            };
          }
        ];
      };
    };
  };

  services.dsh = {
    enable = true;
    package = pkgs.dsh.dsh;
    # Not a secret: hipfire ignores the Authorization header. The credential
    # seam layers the process environment above ~/.dsh/.credentials.yaml, so
    # this satisfies pi-ai's api-key check without writing to the store.
    environment.HIPFIRE_API_KEY = "local";
  };
}
