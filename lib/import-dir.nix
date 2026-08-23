{lib}: path:
map (f: path + "/${f}") (
  builtins.filter (f: f != "default.nix" && lib.hasSuffix ".nix" f)
  (builtins.attrNames (builtins.readDir path))
)
