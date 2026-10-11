# Build the module paths in `path`: every .nix file except default.nix, so a
# directory of modules can be imported with one `importDir ./dir` call and
# adding a file is enough to add a module.
{lib}: path:
map (f: path + "/${f}") (
  builtins.filter (f: f != "default.nix" && lib.hasSuffix ".nix" f)
  (builtins.attrNames (builtins.readDir path))
)
