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

    # Nous Research's agent harness. Imported per-user (see
    # users/snowyrenard/hermes.nix) rather than for every user: it is an agent
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

    buildSystem = {
      host,
      users,
      overlays,
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

          # Only the overlay groups this host names. They apply to the whole
          # system, so they get their own module instead of being folded into
          # the Home Manager one below.
          {
            nixpkgs.overlays = nixpkgs.lib.concatMap (group: overlayGroups.${group}) overlays;
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
        # The only machine that runs the media stack.
        overlays = ["nur" "amethyst" "media"];
      };
      nixos-laptop = {
        dir = "nixos-laptop";
        users = ["snowyrenard"];
        overlays = ["nur" "amethyst"];
      };
      alex-desktop = {
        dir = "AlexDesktop";
        users = ["alexander"];
        # alexander's browser takes the add-ons; nothing else here is used.
        overlays = ["nur"];
      };
    };

    # Overlays by consumer, so a host names what it needs instead of listing
    # six: nur carries the firefox add-ons both users' browsers take, amethyst
    # is the mod manager snowyrenard's NXM handlers name, media is the three
    # packages only system/server/media refers to (behind device.app.jellyfin
    # and device.app.music), and minecraft is what the disabled minecraft tree
    # would need.
    overlayGroups = {
      nur = [nur.overlays.default];
      amethyst = [(import ./overlays/amethyst-mod-manager.nix)];
      media = [
        (import ./overlays/seerrng.nix)
        (import ./overlays/soularr.nix)
        (import ./overlays/houndarr.nix)
      ];
      minecraft = [nix-minecraft.overlay];
    };

    nixosConfigurations =
      nixpkgs.lib.mapAttrs (
        _: machine:
          buildSystem {
            host = machine.dir;
            inherit (machine) users overlays;
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
    # `users/snowyrenard/hermes.nix` reads `osConfig` (the local model ids and
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

      # The Python here was only ever linted as a side effect of a build: the
      # media scripts get it from pkgs.writers.writePython3Bin, which runs
      # flake8, but that leaves the shared arr_client module (read by
      # writeTextDir, not linted) and every script no module builds unchecked.
      # Same command as the writer runs, so a script that passes here cannot
      # then fail its own build on a style rule.
      python =
        pkgs.runCommand "python-lint-check" {
          nativeBuildInputs = [pkgs.python3Packages.flake8 pkgs.findutils];
          src = ./.;
        } ''
          cd "$src"
          flake8 --show-source --ignore=E501 $(find . -name '*.py' -not -path './.git/*')
          touch "$out"
        '';

      # The shell that sits in the tree as files: `test.sh` and the scripts a
      # module reads with `builtins.readFile` (`homepage-env.sh`), neither of
      # which any build lints. Shell written inside a Nix string is still
      # invisible here - but that shell belongs to `writeShellApplication`,
      # whose own checkPhase runs shellcheck, so what is left is exactly these.
      shell =
        pkgs.runCommand "shell-lint-check" {
          nativeBuildInputs = [pkgs.shellcheck pkgs.findutils];
          src = ./.;
        } ''
          cd "$src"
          shellcheck $(find . -name '*.sh' -not -path './.git/*')
          touch "$out"
        '';

      # The counterpart of shell: every feature module declares its own toggle
      # (`options.device.<area>.<stem>.enable`), so the option is greppable in
      # the file that owns it instead of being generated from the file name by
      # a metaprogram. Modules that are deliberately unconditional declare none
      # and are named here, which makes adding one a deliberate edit rather than
      # the consequence of forgetting a line. This replaces `system/options.nix`,
      # which produced the options; a check is all that generator was buying.
      toggles =
        pkgs.runCommand "toggle-check" {
          nativeBuildInputs = [pkgs.gnugrep];
          src = ./.;
        } ''
          cd "$src"
          unconditional="system/security/web-jails.nix system/wm/fonts.nix system/wm/pipewire.nix system/wm/wayland.nix"
          for f in system/{app,hardware,security,wm}/*.nix; do
            area="''${f#system/}"
            area="''${area%%/*}"
            stem="$(basename "$f" .nix)"
            grep -q "options\.device\.$area\.$stem\.enable" "$f" && continue
            case " $unconditional " in
              *" $f "*) ;;
              *)
                echo "$f declares no toggle and is not on the unconditional list" >&2
                echo "either add options.device.$area.$stem.enable or name the file in that list" >&2
                exit 1
                ;;
            esac
          done
          touch "$out"
        '';
    };

    # The flake's own helper commands live in lib/flake-packages.nix; this
    # file stays an entry point: inputs, hosts, and where each piece lives.
    packages.x86_64-linux = import ./lib/flake-packages.nix {inherit pkgs;};
  };
}
