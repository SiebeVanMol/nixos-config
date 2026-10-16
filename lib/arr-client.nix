# The shared *arr client (system/server/media/arr_client.py) as a directory a
# wrapper can put on PYTHONPATH.
#
# Every media script that talks to an *arr API imports it, and each script stays
# a standalone file in the store - so the module that builds one passes
# `makeWrapperArgs = ["--set" "PYTHONPATH" "${arrClient}"]` to
# pkgs.writers.writePython3Bin rather than the client being copied into six
# scripts.
#
# `writeTextDir` rather than a path literal to the repository: PYTHONPATH wants a
# directory holding importable modules, and the media/ directory next to it also
# holds .nix files and a shell script.
{pkgs}: pkgs.writeTextDir "arr_client.py" (builtins.readFile ../system/server/media/arr_client.py)
