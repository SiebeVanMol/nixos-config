# Snowy's installed programs: dev tools, games, media, productivity apps.
{pkgs, ...}: let
  # The compilers, build tools and language servers he programs with have one
  # home and one definition: users/snowyrenard/programming.nix.
  programming = import ./programming.nix {inherit pkgs;};
  # Applied here instead of to the host's pkgs: this user is the only consumer, and
  # a host-level overlay would build the AppImage wrapper for a machine that never
  # names the package. The flake still exposes it as .#amethyst-mod-manager so
  # overlays/update.nu has an attribute to rewrite.
  amethyst-mod-manager = (import ../../overlays/amethyst-mod-manager.nix pkgs pkgs).amethyst-mod-manager;
in {
  home.packages = with pkgs;
    [
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
      # Rust: rustup owns the toolchains here and honours rust-toolchain.toml, so
      # the nixpkgs rustc and cargo the agent needs stay off this PATH.
      rustup
      # Cargo
      cargo-expand
      cargo-tarpaulin
      cargo-flamegraph
      cargo-all-features
      # Code tools
      man-pages

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
      neovim
      mono
      godot-mono
    ]
    ++ programming.toolchain;

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
        # Caelestia writes ~/.config/btop/themes/caelestia.theme from the current
        # colour scheme and sends btop SIGUSR2, which re-reads it. Naming the theme
        # here is what makes btop follow the shell's light/dark and wallpaper colours
        # instead of ignoring the generated file.
        color_theme = "caelestia";
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
  };
}
