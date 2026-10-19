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
| `features/` | one thing that exists on both sides: `hermes/` (the model server and the agent that reads it), `shell/` (which shell an account logs into, the configuration Home Manager writes for it, the terminal that launches it) and `hyprland/` (the compositor session and the bindings) |
| `users/<name>/` | one person: `home.nix` (imports `home/core.nix` plus their own files), programs, editor, browser, and anything personal |
| `lib/` | plain functions, never modules: the `/Vault` layout, btrfs mounts, *arr facts, the webhook client, `import-dir` |
| `overlays/` | packages nixpkgs lacks or carries too old, each pinned by hash in the file that uses it, with `overlays/update.nu` comparing those pins against upstream |

A feature that exists on both sides gets a `features/<name>/` directory with a
`system.nix` and a `home.nix`, because the machine half and the user half then
sit beside each other instead of three directories apart. `features/default.nix`
imports every machine half; a user imports the user half it runs, so a feature
one person uses never lands in another person's home. Hermes is the example:
the model server was `system/server/ai/` and the agent `users/snowyrenard/`,
and the second read the first through `osConfig` across the gap.

A directory here is earned by spanning both sides, and the test is "one fact,
one place" rather than "how many lines". `system/app/steam.nix` and
`home/caelestia.nix` stay where they are: a thing that is only machine-wide or
only in someone's home is not a feature by this definition. The shell is a
feature with a one-line machine half, and that is exactly why: three places had
to name the same program - the account's `shell`, the Home Manager
configuration's `programs.nushell`, and the terminal's `shell =` - and one of
them silently disagreeing is a session that starts a shell the account does not
have. `device.shell.program` is now the only place that fact lives, with
`device.shell.terminal` beside it for the terminal.

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

Scripts are **nushell**: `pkgs.writers.writeNuBin` (or `writeNu` for a
non-executable), or a `.nu` file a module reads. Not bash - `parse`, `to json`,
`http post`, `str`, `path` and tables replace sed/awk/jq/curl/coreutils
pipelines, and the data is typed at every step. A shell that needs bash anyway
says why in its header comment.

The Python beside the modules (`system/server/media/`,
`system/server/minecraft/`) is checked by the flake, and
`checks.x86_64-linux.shell` shellchecks the `*.sh` files that remain.
`checks.x86_64-linux.nu` is what parses the nushell: `nu --ide-check 10 <file>`
prints diagnostics on stdout and still exits 0, so the check makes the error
severity lines fatal (the type hints are not problems). It covers `*.nu` files in
the tree; a nushell string inside a module is only parsed when that module's
program is built, which for a `writeNuBin` means the file is read, not run.

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

`features/hermes/home.nix` owns the install, and the module runs in managed
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
