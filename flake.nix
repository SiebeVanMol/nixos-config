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

      # A nushell script is parsed by nothing: `nu --ide-check` prints
      # diagnostics on stdout and still exits 0, so a build of a .nu file proves
      # only that the file exists. This makes the errors fatal - the counterpart
      # of `shell` for the scripts that are not shell scripts. Hints are ignored
      # (they are types, not problems), which is why the output is filtered
      # rather than merely checked for emptiness.
      nu =
        pkgs.runCommand "nu-parse-check" {
          nativeBuildInputs = [pkgs.nushell pkgs.ripgrep pkgs.findutils];
          src = ./.;
        } ''
          cd "$src"
          rc=0
          for f in $(find . -name '*.nu' -not -path './.git/*'); do
            # not `out`: that is the derivation's output path, and assigning to
            # it is how this check failed to produce one the first time.
            errors=$(nu --ide-check 10 "$f" | rg '"severity":"Error"' || true)
            if [ -n "$errors" ]; then
              echo "== $f"
              echo "$errors"
              rc=1
            fi
          done
          if [ "$rc" -eq 0 ]; then touch "$out"; fi
          exit "$rc"
        '';

      # A feature is two halves of one thing, so a directory under features/ must
      # carry both, and its machine half must be imported below or it never loads.
      # The counterpart of `toggles`: a convention is worth having only if half of
      # it cannot go missing quietly - a home-only directory filed here would be
      # exactly that, and it belongs in home/ with the rest of the one-sided
      # configuration.
      features =
        pkgs.runCommand "feature-halves-check" {
          nativeBuildInputs = [pkgs.gnugrep];
          src = ./.;
        } ''
          cd "$src"
          rc=0
          for d in features/*/; do
            d="''${d%/}"
            name="''${d#features/}"
            # a half is `half.nix` or a `half/` directory with a default.nix
            # (shell's user half is a directory of its own files).
            for half in system home; do
              if [ ! -e "$d/$half.nix" ] && [ ! -e "$d/$half/default.nix" ]; then
                echo "$d: no $half.nix - a feature has both halves"
                rc=1
              fi
            done
            if ! grep -qF "    ./$name/system.nix" features/default.nix; then
              echo "$d: not imported by features/default.nix, so it never loads"
              rc=1
            fi
          done
          if [ "$rc" -eq 0 ]; then touch "$out"; fi
          exit "$rc"
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
    # The helper commands (lib/flake-packages.nix) plus the four overlay
    # packages, which are addressable here and nowhere else: `nix-update` needs
    # an attribute to rewrite, and `nix build .#seerrng` should work without a
    # host in the middle.
    packages.x86_64-linux =
      (import ./lib/flake-packages.nix {inherit pkgs;})
      // {inherit (overlayPackages) seerrng soularr houndarr amethyst-mod-manager;}
      // {
        # The Home Manager CLI from the *locked* input. The NixOS module brings the
        # library, not the command, so `home-manager switch` - the no-root path the
        # task menu offers - had nothing to run. Taking it from the input keeps the
        # version identical to the one NixOS itself would activate.
        home-manager = home-manager.packages.x86_64-linux.home-manager;
      };
  };
}
