# Print Prowlarr's indexers and SeerrNG's service links as a paste-ready Nix
# snippet. Read-only, and root-only because both APIs are.
#
# A shim on purpose: the work is system/server/media/servarr-sync.py, and the
# wrapper that gives it lib/arr-client.nix on PYTHONPATH is built in
# lib/flake-packages.nix and placed on PATH there. Keeping the store path out of
# this file means it is plain nushell that `checks.nu` can parse.
# `--wrapped`: without it nushell eats `--apply`, `--help`, `--flake` and friends as
# its own flags and the program never sees them (nushell's own help was what
# `nix run .#servarr-export -- --help` printed before this).
def --wrapped main [...args: string] {
  ^servarr-sync-export ...$args
  exit $env.LAST_EXIT_CODE
}
