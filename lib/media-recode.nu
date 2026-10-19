# Re-encode the library's over-encoded tail, measured by bits-per-pixel, and
# refresh each application's record so its native-upgrade hunt keeps working.
# Dry run unless --apply.
#
# A shim on purpose: the work is system/server/media/media-recode.py. Its wrapper
# carries PYTHONPATH, the ARR_APPS default and the AMF library path (ffmpeg
# dlopen()s AMD's runtime, so av1_amf needs it on the loader path) and put on PATH
# in lib/flake-packages.nix.
# `--wrapped`: without it nushell eats `--apply`, `--help`, `--flake` and friends as
# its own flags and the program never sees them (nushell's own help was what
# `nix run .#servarr-export -- --help` printed before this).
def --wrapped main [...args: string] {
  ^media-recode ...$args
  exit $env.LAST_EXIT_CODE
}
