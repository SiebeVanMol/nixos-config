# Format the tree, then run nixos-rebuild with --flake filled in and sudo added
# for the subcommands that need it.
#
# Ported from bash by hand rather than by translation: `nix run .#rebuild` starts in
# the caller's directory, so the flake root has to be found first, and the sudo
# decision comes from the subcommand the user typed (switch/boot/test/rollback/
# build-vm-with-bootloader), not from a flag.
# `--wrapped`: without it nushell eats `--apply`, `--help`, `--flake` and friends as
# its own flags and the program never sees them (nushell's own help was what
# `nix run .#servarr-export -- --help` printed before this).
def --wrapped main [...args: string] {
  mut root = $env.PWD
  while $root != "/" and not (($root | path join "flake.nix") | path exists) {
    $root = ($root | path dirname)
  }
  if not (($root | path join "flake.nix") | path exists) {
    print -e $"error: could not find flake.nix from ($env.PWD)"
    exit 1
  }

  cd $root
  ^nix fmt .

  # Only add --flake if the caller did not already pass one.
  mut argv = [...$args]
  if not ($argv | any {|arg| $arg | str contains "--flake" }) {
    $argv = ["--flake" $root ...$argv]
  }

  let needs_sudo = ($argv | any {|arg|
      $arg in ["switch" "boot" "test" "rollback" "build-vm-with-bootloader"]
    })

  let result = (if $needs_sudo { ^sudo nixos-rebuild ...$argv } else { ^nixos-rebuild ...$argv })
  exit ($env.LAST_EXIT_CODE)
}
