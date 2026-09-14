# Flake entry point defining all NixOS system configurations and their inputs.
# Provides three machines, each carrying one or more users. nixos-desktop and
# nixos-laptop currently have user snowyrenard; alex-desktop has user alexander.
# To add more users to a host, extend the `users` list below (each entry needs a
# matching ./users/<name>/home.nix).
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

    llm-agents.url = "github:numtide/llm-agents.nix";

    # Fetched over SSH (uses the user's GitHub SSH key) so GitHub's HTTPS
    # archive/API rate limit can't stall the build.
    caelestia-shell = {
      url = "git+ssh://git@github.com/caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    home-manager,
    nur,
    vpn-confinement,
    nix-minecraft,
    llm-agents,
    ...
  }:
  # Helper to build a system configuration for a host with one or more users.
  #
  # `users` is a list of usernames, each backed by `./users/<name>/home.nix`.
  # Per-user Home Manager config is set up for every user, and NixOS account
  # creation and group memberships apply to every listed user. Nothing in the
  # configuration assumes a single "primary" user: system services that need a
  # home or session either discover it at runtime or live under neutral paths.
  let
    # Plain nixpkgs (no overlays), used for the flake's own outputs: the
    # formatter, the formatting check and the rebuild wrapper.
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    buildSystem = {
      host,
      users,
    }:
      nixpkgs.lib.nixosSystem {
        # Modules receive the list as `usernames`.
        specialArgs = {usernames = users;};
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
              llm-agents.overlays.shared-nixpkgs
              (import ./overlays/amethyst-mod-manager.nix)
              (import ./overlays/bookshelf.nix)
              (import ./overlays/kapowarr.nix)
              (import ./overlays/seerrng.nix)
              (import ./overlays/shadps4.nix)
            ];
          }

          # Home Manager: declarative per-user package and dotfile management.
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Only flake inputs are shared globally here. Per-user values like
            # `username`/`homeDirectory` are derived by Home Manager itself from
            # each `users.users.<name>`, so they are NOT passed as specialArgs.
            home-manager.extraSpecialArgs = inputs;

            # One Home Manager configuration per user on this host.
            home-manager.users = builtins.listToAttrs (map (username: {
                name = username;
                value = import ./users/${username}/home.nix;
              })
              users);
          }
        ];
      };
  in {
    formatter.x86_64-linux = pkgs.alejandra;

    checks.x86_64-linux = {
      formatting =
        pkgs.runCommand "nix-formatting-check" {
          nativeBuildInputs = [pkgs.alejandra];
          src = nixpkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              (baseNameOf path != "result")
              && (nixpkgs.lib.cleanSourceFilter path type);
          };
        } ''
          cd "$src"
          alejandra --check .
          touch "$out"
        '';
    };

    packages.x86_64-linux = let
      rebuild = pkgs.writeShellScriptBin "rebuild" ''
        set -euo pipefail

        # Find the flake root (directory containing flake.nix).
        ROOT="$(pwd)"
        while [[ "$ROOT" != "/" && ! -f "$ROOT/flake.nix" ]]; do
          ROOT="$(dirname "$ROOT")"
        done
        if [[ ! -f "$ROOT/flake.nix" ]]; then
          echo "error: could not find flake.nix from $(pwd)" >&2
          exit 1
        fi

        cd "$ROOT"
        ${pkgs.nix}/bin/nix fmt .

        # Only add --flake if the user didn't already pass one.
        if [[ "$*" != *"--flake"* ]]; then
          set -- --flake "$ROOT" "$@"
        fi

        needs_sudo=false
        for arg in "$@"; do
          case "$arg" in
            switch|boot|test|rollback|build-vm-with-bootloader)
              needs_sudo=true
              ;;
          esac
        done

        if $needs_sudo; then
          exec sudo nixos-rebuild "$@"
        else
          exec nixos-rebuild "$@"
        fi
      '';
    in {
      inherit rebuild;
    };

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
