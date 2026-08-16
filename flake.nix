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

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, nur, vpn-confinement, nix-minecraft, ... }:
    # Helper to build a system configuration for a given user + host pair.
    let
      buildSystem = { user, host }:
        let
          username = user;
          specialArgs = { inherit username; };
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
                ];
              }
            ];
          };
    in
    {
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
