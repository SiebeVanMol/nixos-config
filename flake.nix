{
  description = "NixOS configuration";
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
  };

  outputs = inputs@{ nixpkgs, home-manager, nur, vpn-confinement, ... }:
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
              # Host device configurations
              ./hosts/${host}

              vpn-confinement.nixosModules.default
              # General home manager config and user changes
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs = inputs // specialArgs;
                home-manager.users.${username} = import ./users/${username}/home.nix;

                
                nixpkgs.overlays = [
                  nur.overlays.default
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
          host = "alex-desktop";
        };
      };
    };
}
