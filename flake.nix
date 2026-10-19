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

    # vpn-confinement declares no inputs of its own, so it has nothing to follow -
    # saying `inputs.nixpkgs.follows` here only earns "override for a non-existent
    # input 'nixpkgs'" at every evaluation.
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

    # nix-minecraft does pin its own nixpkgs; following the top-level one keeps a
    # second, older copy out of flake.lock. Its overlay and module are applied to
    # this flake's pkgs anyway, so the copy was only ever used by its own checks.

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nous Research's agent harness. Imported per-user (see
    # features/hermes/home.nix) rather than for every user: it is an agent
    # for one person, whose credentials and memory belong to that person.
    # nixpkgs follows the top-level input so uv2nix resolves against the same
    # package set instead of a second pinned copy.
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

    # One shape for every check: a nushell script in lib/checks/ is the derivation's
    # builder. `builder` + `args` rather than `runCommand`, so nushell is the program
    # that runs and no bash is involved at all. The script reads the tree from
    # `$env.src`, calls its linter through a `*_BIN` placeholder replaced here with an
    # absolute store path (a custom builder gets none of stdenv's setup, so there is no
    # PATH to find it on), and writes `$env.out` when it passes.
    # `builtins.derivation`, not `mkDerivation`: mkDerivation keeps bash as the builder
    # and only takes `args` from here, so the script arrived as a *bash* script
    # ("syntax error near unexpected token `('"). A raw derivation honours `builder`.
    # HOME is set because nushell wants a config directory and the sandbox's default
    # ($HOME = /homeless-shelter) is not writable; /build is where the build runs.
    check = name: script: bins:
      builtins.derivation {
        inherit (pkgs.stdenvNoCC) system;
        name = "${name}-check";
        builder = "${pkgs.nushell}/bin/nu";
        args = [
          (pkgs.writeText "${name}-check.nu" (
            pkgs.lib.replaceStrings (builtins.attrNames bins) (builtins.attrValues bins) (builtins.readFile script)
          ))
        ];
        src = ./.;
        HOME = "/build";
        NO_COLOR = "1";
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

          # Home Manager: declarative per-user package and dotfile management.
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            # false, so Home Manager owns its own profile at
            # ~/.local/state/nix/profiles/home-manager (linked as ~/.nix-profile) and
            # `home-manager switch` can install a program by itself. With `true` the
            # packages go into the NixOS per-user profile, which only nixos-rebuild
            # writes - a newly declared program was built into the generation and then
            # stayed off PATH until a full system rebuild. `~/.nix-profile/bin` is on
            # this system's default PATH (second entry), so nothing else is needed.
            home-manager.useUserPackages = false;
            # Flake inputs are shared globally here, individually and under
            # `inputs`. Per-user values are derived by Home Manager from each
            # users.users.<name>, so they are NOT passed as specialArgs.
            home-manager.extraSpecialArgs = inputs // {inherit inputs;};

            # One Home Manager configuration per user on this host.
            home-manager.users = nixpkgs.lib.genAttrs users (username: {
              imports = [
                (import ./users/${username}/home.nix)
              ];
            });
          }
        ];
      };

    # One table of machines: the attribute name (also what `test.sh` and the
    # Home Manager aliases use), the directory under ./hosts, and the users
    # that host runs. Both output sets below are derived from it, so adding a
    # machine or a user stays one edit. The directory is not derived from the
    # attribute: alex-desktop's is capitalised.
    hosts = {
      nixos-desktop = {
        dir = "nixos-desktop";
        users = ["snowyrenard"];
      };
      nixos-laptop = {
        dir = "nixos-laptop";
        users = ["snowyrenard"];
      };
      alex-desktop = {
        dir = "AlexDesktop";
        users = ["alexander"];
      };
    };

    # The four pins in overlays/, composed for the package outputs below and
    # nothing else. Hosts no longer take an overlay list: each consumer applies its
    # own overlay (system/server/media/*.nix inside the service's gate,
    # users/snowyrenard/{programs,browser}.nix by importing the file), so a machine
    # that does not use a pin never evaluates it. nur and nix-minecraft are not
    # here - every host needs their modules or packages, and both are used through
    # the input directly.
    overlayGroups = {
      amethyst = [(import ./overlays/amethyst-mod-manager.nix)];
      media = [
        (import ./overlays/seerrng.nix)
        (import ./overlays/soularr.nix)
        (import ./overlays/houndarr.nix)
      ];
    };

    # The overlay packages as first-class outputs, for two practical reasons:
    # `nix build .#seerrng` builds one pin on its own, and `nix-update` can only
    # rewrite a version and hash it can name as an attribute. Until now these
    # four existed only inside a host's configuration, which is why the pins in
    # overlays/ had no address for a tool to find - and why they could sit
    # behind upstream without anyone noticing.
    overlayPackages = pkgs.extend (
      nixpkgs.lib.composeManyExtensions (overlayGroups.amethyst ++ overlayGroups.media)
    );

    nixosConfigurations =
      nixpkgs.lib.mapAttrs (
        _: machine:
          buildSystem {
            host = machine.dir;
            inherit (machine) users;
          }
      )
      hosts;

    # The Home Manager configuration NixOS already evaluates for a user,
    # re-exported so it can be activated on its own:
    #
    #   home-manager switch --flake .#snowyrenard@nixos-desktop
    #
    # That builds the same activation package `nixos-rebuild switch` would
    # (the store path is the same derivation, not a second evaluation that has
    # to be kept in step), and touches only the home tree - no boot loader, no
    # system units, no root. A system-level change still needs the full
    # rebuild, which continues to carry Home Manager with it.
    #
    # Taken from the NixOS side rather than assembled again for two reasons:
    # `features/hermes/home.nix` reads `osConfig` (the local model ids and
    # the loopback port), which only exists inside a NixOS evaluation, and a
    # second module list would be free to drift from the first.
    #
    # Both entry points write the same Home Manager generation directory, so
    # whichever ran last wins - harmless while the derivation is identical,
    # and the reason a change under `system/` is never visible until the full
    # rebuild runs.
    homeConfigurations = nixpkgs.lib.listToAttrs (
      nixpkgs.lib.concatLists (
        nixpkgs.lib.mapAttrsToList (
          host: machine:
            map (user: let
              hm = nixosConfigurations.${host}.config.home-manager.users.${user};
            in {
              name = "${user}@${host}";
              # The attributes `homeManagerConfiguration` puts on its result
              # (`modules/default.nix`): `config` for what the CLI reads out of
              # it (news among them), the activation package it installs, and the
              # package set it evaluates against. `hm` *is* that config, so it
              # serves as both the value and its `config`.
              value =
                hm
                // {
                  config = hm;
                  inherit (hm.home) activationPackage;
                  activation-script = hm.home.activationPackage;
                  inherit (hm._module.args) pkgs;
                };
            })
            machine.users
        )
        hosts
      )
    );
  in {
    inherit nixosConfigurations homeConfigurations;

    formatter.x86_64-linux = pkgs.alejandra;

    checks.x86_64-linux = {
      # Six checks, one shape. The reasoning for each lives at the top of its script
      # in lib/checks/, next to the code it explains.
      formatting = check "nix-formatting" ./lib/checks/formatting.nu {
        ALEJANDRA_BIN = "${pkgs.alejandra}/bin/alejandra";
      };

      python = check "python-lint" ./lib/checks/python.nu {
        FLAKE8_BIN = "${pkgs.python3Packages.flake8}/bin/flake8";
      };

      shell = check "shell-lint" ./lib/checks/shell.nu {
        SHELLCHECK_BIN = "${pkgs.shellcheck}/bin/shellcheck";
      };

      nu = check "nu-parse" ./lib/checks/nu.nu {
        NU_BIN = "${pkgs.nushell}/bin/nu";
      };

      features = check "feature-halves" ./lib/checks/features.nu {};

      toggles = check "toggle" ./lib/checks/toggles.nu {};
    };
  };
}
