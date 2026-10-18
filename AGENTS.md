# Working in this repository

NixOS + Home Manager flake for three machines: hosts `nixos-desktop`,
`nixos-laptop` and `alex-desktop`. The `nixosConfigurations` attribute is
`alex-desktop` as well — the directory is `hosts/AlexDesktop` and its hostname
is `alex-desktop`, and `test.sh` compares the hostname case-insensitively for
that reason. `hosts/` names each machine's users, `users/<name>/` is the
per-user tree, `system/` the shared system tree, `home/` the shared Home
Manager tree, `lib/` the helpers, `overlays/` the package overrides.

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

## How the code reads

The comments carry the reasoning. A non-obvious choice states the constraint
that forced it, and often the alternative that was rejected and the failure it
would have caused — several are longer than the code they explain. A change
without its "why" is unfinished here. Alejandra owns the formatting.

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
