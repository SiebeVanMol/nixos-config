# flake8 over every *.py in the tree, with the same flags `pkgs.writers.writePython3Bin`
# runs, so a script that passes here cannot then fail its own build on a style rule.
def main [] {
  cd $env.src
  let files = (glob **/*.py)
  if ($files | is-empty) {
    "" | save -f $env.out
    return
  }
  let run = (do -i { ^FLAKE8_BIN --show-source --ignore=E501 ...$files } | complete)
  print -n $run.stdout
  print -e -n $run.stderr
  if $run.exit_code != 0 {
    exit $run.exit_code
  }
  "" | save -f $env.out
}
