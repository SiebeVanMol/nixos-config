# Working in this repository

NixOS + Home Manager flake for three machines: hosts `nixos-desktop`,
`nixos-laptop` and `alex-desktop`. The `nixosConfigurations` attribute is
`alex-desktop` as well — the directory is `hosts/AlexDesktop` and its hostname
is `alex-desktop`, and `test.sh` compares the hostname case-insensitively for
that reason.

`flake.nix` is the entry point and only that: the inputs, one table naming each
machine, its `./hosts` directory and its users, and the outputs derived from it
(`nixosConfigurations`, `homeConfigurations`, `checks`, `packages`).

## Where things live

One question per directory, so the path answers what is in here:

| Path | Holds |
| --- | --- |
| `hosts/<Host>/` | one machine: its `hardware-configuration.nix` and the `device.*` toggles it switches on |
| `system/` | everything machine-wide and shared by all three: accounts, boot and locale in `default.nix`; features in `app/ hardware/ security/ wm/`; recurring jobs in `maintenance/`; long-running services in `server/` |
| `home/` | the Home Manager settings every user gets — `core.nix` pulls in the shell, Hyprland, wallpapers, input method and desktop apps |
| `users/<name>/` | one person: `home.nix` (imports `home/core.nix` plus their own files), programs, editor, browser, and anything personal — `hermes.nix` for Snowy |
| `lib/` | plain functions, never modules: the `/Vault` layout, btrfs mounts, *arr facts, the webhook client, `import-dir` |
| `overlays/` | packages nixpkgs lacks or carries too old, each pinned by hash in the file that uses it |

A few features legitimately straddle two trees, and they are named here so
nobody has to discover it: the local model server (`system/server/ai`) is read
through `osConfig` by `users/snowyrenard/hermes.nix`, and the shell is
`home/shell/*` against the default shell set in `system/default.nix`. Both are
deliberate — a user module needs the machine's port and model ids, and the
shell has to be the same program for the account and the session.

## Verification

`./test.sh` is the single entry point and the only thing that counts as a
check: alejandra's format check, `nix flake check`, then evaluation of every
host — `config.system.build.toplevel.drvPath`, which is what walks unit text
and service configuration — plus a hostname assertion per host. The host list
is read from `nixosConfigurations`, so a new machine is covered with no edit.

Two traps:

- `nix flake check` reads the **git tree**: a new file has to be `git add`ed
  before the check can see it.
- The agent's shell has no `sudo`. `nixos-rebuild switch` and `systemctl` are
  not available, so a change is verified by evaluating and building
  derivations, and runtime effects land on the owner's next rebuild. Report
  that honestly instead of implying a service was restarted.

Evals and builds are slow here and are the normal cost of changing anything:
run them rather than reporting that they would pass.

Home Manager changes have a second, shorter path that needs no root:
`home-manager switch --flake .#<user>@<host>` activates exactly the generation
`nixos-rebuild switch` would, because the flake re-exports each host's
NixOS-evaluated Home Manager configuration under `homeConfigurations`. The two
entry points build the same derivation (`home.activationPackage`), so whichever
ran last leaves the same profile; anything under `system/` still needs the full
rebuild.

## How the code reads

The comments carry the reasoning. A non-obvious choice states the constraint
that forced it, and often the alternative that was rejected and the failure it
would have caused — several are longer than the code they explain. A change
without its "why" is unfinished here. Alejandra owns the formatting.

A feature is a file in `system/{app,hardware,security,wm}/`, and it declares its
own `options.device.<area>.<file>.enable` — a host switches it on with one line
under `device`. `checks.x86_64-linux.toggles` fails if a module there declares
none and is not named in its unconditional list, so the naming rule cannot rot
silently. Nothing generates those options: `options` is where they are.

The Python beside the modules (`system/server/media/`,
`system/server/minecraft/`) is checked by the flake. Shell is only `bash -n`
clean, so read it before trusting it.

## Open work

`todo.md` is the list, most valuable first, and it separates what a read-only
pass verified from what nobody has measured. Add an entry there instead of
leaving a TODO in the code, and keep that distinction intact.

## Commits

Subjects are imperative and sentence case, with no `type:` prefixes and no
file names — they describe the change ("Lint the Python the flake never
checked"). One logical change per commit. The tree stays clean of anything
that is not part of the change: test scripts, probes, `result` symlinks and
build output belong outside the repository. Pushes are batched — one push once
a workstream is finished, not one per commit.

## Hermes, which this repository installs

`users/snowyrenard/hermes.nix` owns the install, and the module runs in managed
mode: `hermes config set` and `hermes setup` refuse to run there, naming
`home-manager switch` instead. Configuration is changed here, not at runtime.
Settings go in `services.hermes-agent.settings`, files that belong in
`HERMES_HOME` (SOUL.md, memory) in `hermesHomeFiles`, and any tool the agent's
shell should reach in `extraPackages`. Secrets never enter this repository —
the API key is read from `~/.config/hermes/env` and merged into
`~/.hermes/.env` at activation.

`extraPackages` is the agent's entire PATH: hermes, bash, coreutils and git,
then the three lists in `users/snowyrenard/programming.nix` — the language
servers and toolchains shared with the shell and the editor, plus what only the
agent needs. Nothing from a shell profile, a dev shell or `~/.cargo/bin` is on
it, so a command that works in the user's terminal can still be missing here;
the fix is a line in that file, not a wrapper script.

Language servers are trust-gated, and a server declared under `lsp.servers`
always is. nixd, rust-analyzer and csharp-ls therefore start only in a
workspace the operator pointed Hermes at — a session started inside the
project, a Desktop project, or the gateway's `terminal.cwd`. A session running
from the home directory has no such anchor, so those servers stay dormant and
the log carries `skipped: untrusted workspace`. clangd, pyright and
bash-language-server are exempt and run anywhere. The committed configuration
deliberately lists no trusted directory: the gate is the session's workspace,
not a path allowlist.
