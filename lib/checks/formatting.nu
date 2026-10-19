# `alejandra --check` over the tree. The `*_BIN` placeholders are replaced with
# absolute store paths by flake.nix, because a custom derivation builder gets none of
# stdenv's setup and therefore no PATH.
def main [] {
  cd $env.src
  let run = (do -i { ^ALEJANDRA_BIN --check . } | complete)
  print -n $run.stdout
  print -e -n $run.stderr
  if $run.exit_code != 0 {
    exit $run.exit_code
  }
  "" | save -f $env.out
}
