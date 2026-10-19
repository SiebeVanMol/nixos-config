# Ask every *arr application to search its indexers for better releases of the
# whole library - the front-loading counterpart to Houndarr's five-an-hour cap.
# Root because the API keys live in 0700 config files; dry run unless --apply.
#
# A shim on purpose: the work is system/server/media/servarr-sweep.py, whose
# wrapper (PYTHONPATH plus the ARR_APPS default) is built in
# lib/flake-packages.nix and put on PATH there.
# `--wrapped`: without it nushell eats `--apply`, `--help`, `--flake` and friends as
# its own flags and the program never sees them (nushell's own help was what
# `nix run .#servarr-export -- --help` printed before this).
def --wrapped main [...args: string] {
  ^servarr-sweep ...$args
  exit $env.LAST_EXIT_CODE
}
