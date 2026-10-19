# shellcheck over the *.sh files that live in the tree as files. Shell inside a Nix
# string is not covered here - that belongs to `writeShellApplication`, whose own
# checkPhase runs shellcheck.
def main [] {
  cd $env.src
  let files = (glob **/*.sh)
  if ($files | is-empty) {
    "" | save -f $env.out
    return
  }
  let run = (do -i { ^SHELLCHECK_BIN ...$files } | complete)
  print -n $run.stdout
  print -e -n $run.stderr
  if $run.exit_code != 0 {
    exit $run.exit_code
  }
  "" | save -f $env.out
}
