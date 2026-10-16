# Snowy's programming tools: the compilers, build tools and language servers
# for the languages he works in (Nix, Rust, C and C++, C#, Python, shell).
#
# One home per user, because the set is a fact about the person and not about a
# program: programs.nix puts the toolchain on the shell's PATH, editor.nix
# gives Helix the servers, and hermes.nix hands everything to the Hermes agent
# as extraPackages. Written once, so the three lists cannot drift apart.
#
# The split is by consumer and not by kind, so nothing lands where it would
# change something silently: a second rustc/cargo or a nixpkgs rust-analyzer on
# the shell's PATH would take toolchain pinning (rust-toolchain.toml) and
# rustup's own rust-analyzer away from the editor.
{pkgs}: rec {
  # Compilers and build tools. Both the shell and the agent get these.
  toolchain = with pkgs; [
    gcc
    gnumake
    cmake
    valgrind
    norminette # the 42 school projects
    dotnet-sdk_8 # Godot's C# projects are net8.0; csharp-ls runs on it
    (python3.withPackages (ps: [ps.mypy ps.flake8]))
  ];

  # Servers that the editor and the agent both resolve. rust-analyzer is not
  # here: rustup provides it, for the editor and the agent alike, so a nixpkgs
  # copy would only shadow it (and collide with the shim - see agentOnly).
  servers = with pkgs; [
    nixd
    clang-tools # clangd
    csharp-ls # Hermes ships no C# server; hermes.nix declares this one
  ];

  # What only the agent needs, and why the shell must not have it.
  #
  # nix: ./test.sh is this repository's only verification entry point and it
  # opens with `nix run`.
  # rustup, and nothing beside it that provides the same commands. rust-analyzer
  # needs cargo on PATH just to load a Cargo workspace, and the shell's rustup is
  # not on this PATH: that one lives in the profile, which the agent's env is not
  # built from. The two cannot coexist anyway - extraPackages become
  # home.packages, whose buildEnv refuses two packages that both install
  # bin/cargo, and rustup's shims are exactly that (that collision is what failed
  # a switch, twice: cargo, then rust-analyzer). So the agent resolves rust
  # through the same rustup the rest of the machine uses, which also means
  # rust-toolchain.toml is honoured for it.
  # shellcheck: the backend bash-language-server delegates to. Without it the
  # server spawns and reports nothing, which reads exactly like a clean file.
  # bear: writes the compile_commands.json clangd reads, which a bare Makefile
  # never produces.
  agentOnly = with pkgs; [
    nix
    rustup
    shellcheck
    bear
  ];
}
