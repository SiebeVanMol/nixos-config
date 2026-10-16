# Flake entry point: inputs, hosts, and where each piece lives. Three machines,
# each with one or more users; to add a user to a host, extend its `users` list
# (each entry needs a matching ./users/<name>/home.nix).
{
  description = "NixOS configuration";

  # Remote flake dependencies pinned by flake.lock.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

    nix-minecraft.url = "github:Infinidoge/nix-minecraft";

    deepseek-harness.url = "github:moraxyc/deepseek-harness.nix";

    # Nous Research's agent harness. Imported per-user (see
    # users/snowyrenard/hermes.nix), not for every user like deepseek-harness:
    # it is an agent for one person, whose credentials and memory belong to
    # that person. nixpkgs follows the top-level input so uv2nix resolves
    # against the same package set instead of a second pinned copy.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    # Fetched over HTTPS rather than SSH: the repository is public, and an input
    # needing a key only builds on a machine whose user has one (alex-desktop does
    # not, so an SSH fetch died before evaluation). `git+https` also speaks the git
    # protocol, so the archive API's anonymous rate limit does not apply.
    caelestia-shell = {
      url = "git+https://github.com/caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    home-manager,
    nur,
    vpn-confinement,
    nix-minecraft,
    deepseek-harness,
    ...
  }:
  # Build a system configuration for a host with one or more users. `users` is a
  # list of usernames, each backed by ./users/<name>/home.nix; nothing assumes a
  # single "primary" user, since services needing a home discover it at runtime
  # or live under neutral paths.
  let
    # Plain nixpkgs (no overlays) for the flake's own outputs. allowUnfree
    # mirrors the hosts because the media recoder's AV1 path goes through AMD's
    # proprietary AMF runtime, the only way to reach this card's AV1 encoder.
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    buildSystem = {
      host,
      users,
    }:
      nixpkgs.lib.nixosSystem {
        # Modules receive the user list as `usernames`, and the shared /Vault
        # layout plus vaultRw helper as `media` (system/server/media/default.nix
        # explains why this is a specialArg rather than _module.args).
        specialArgs = {
          usernames = users;
          media = import ./lib/media.nix {inherit (nixpkgs) lib;};
        };
        system = "x86_64-linux";
        modules = [
          # Machine-specific NixOS config + generated hardware config.
          ./hosts/${host}

          # Third-party modules for Minecraft server and VPN network namespaces.
          nix-minecraft.nixosModules.minecraft-servers
          vpn-confinement.nixosModules.default

          # Overlays adding packages nixpkgs does not carry. They apply to the
          # whole system, so they get their own module instead of being folded
          # into the Home Manager one below.
          {
            nixpkgs.overlays = [
              nur.overlays.default
              nix-minecraft.overlay
              deepseek-harness.overlays.default
              (import ./overlays/dsh-model-router.nix)
              (import ./overlays/amethyst-mod-manager.nix)
              (import ./overlays/seerrng.nix)
              (import ./overlays/soularr.nix)
              (import ./overlays/houndarr.nix)
            ];
          }

          # Home Manager: declarative per-user package and dotfile management.
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Flake inputs are shared globally here, individually and under
            # `inputs`. Per-user values are derived by Home Manager from each
            # users.users.<name>, so they are NOT passed as specialArgs.
            home-manager.extraSpecialArgs = inputs // {inherit inputs;};

            # One Home Manager configuration per user on this host.
            home-manager.users = nixpkgs.lib.genAttrs users (username: {
              imports = [
                deepseek-harness.homeModules.default
                (import ./users/${username}/home.nix)
              ];
            });
          }
        ];
      };
  in {
    formatter.x86_64-linux = pkgs.alejandra;

    checks.x86_64-linux = {
      formatting =
        pkgs.runCommand "nix-formatting-check" {
          nativeBuildInputs = [pkgs.alejandra];
          # `./.` is already the git-tracked tree, and cleanSourceWith's default
          # filter (lib/sources.nix) drops nix-build `result` symlinks, so the
          # hand-written filter that used to wrap this added nothing.
          src = ./.;
        } ''
          cd "$src"
          alejandra --check .
          touch "$out"
        '';
    };

    # The flake's own helper commands live in lib/flake-packages.nix; this
    # file stays an entry point: inputs, hosts, and where each piece lives.
    packages.x86_64-linux = import ./lib/flake-packages.nix {inherit pkgs;};

    nixosConfigurations = {
      nixos-desktop = buildSystem {
        host = "nixos-desktop";
        users = ["snowyrenard"];
      };
      nixos-laptop = buildSystem {
        host = "nixos-laptop";
        users = ["snowyrenard"];
      };
      alex-desktop = buildSystem {
        host = "AlexDesktop";
        users = ["alexander"];
      };
    };
  };
}
