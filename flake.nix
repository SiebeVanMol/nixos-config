# Flake entry point defining all NixOS system configurations and their inputs.
# Provides three machines: nixos-desktop, nixos-laptop (user: snowyrenard), and alex-desktop (user: alexander).
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
  # Helper to build a system configuration for a given user + host pair.
  let
    buildSystem = {
      user,
      host,
    }: let
      username = user;
      specialArgs = {inherit username;};
    in
      nixpkgs.lib.nixosSystem {
        inherit specialArgs;
        system = "x86_64-linux";
        modules = [
          # Machine-specific NixOS config + generated hardware config.
          ./hosts/${host}

          # Third-party modules for Minecraft server and VPN network namespaces.
          nix-minecraft.nixosModules.minecraft-servers
          vpn-confinement.nixosModules.default

          # Home Manager: declarative per-user package and dotfile management.
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = inputs // specialArgs;
            home-manager.users.${username} = import ./users/${username}/home.nix;

            nixpkgs.overlays = [
              nur.overlays.default
              nix-minecraft.overlay
              llm-agents.overlays.shared-nixpkgs
            ];
          }
        ];
      };
  in {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;

    checks.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
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
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
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
        user = "snowyrenard";
        host = "nixos-desktop";
      };
      nixos-laptop = buildSystem {
        user = "snowyrenard";
        host = "nixos-laptop";
      };
      alex-desktop = buildSystem {
        user = "alexander";
        host = "AlexDesktop";
      };
    };
  };
}
