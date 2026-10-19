# Parse every *.nu in the tree. `nu --ide-check` prints diagnostics on stdout and
# still exits 0, so a build of a .nu file proves only that it exists: the Error
# severities are what fail here, and the Hints (types, not problems) are ignored.
def main [] {
  cd $env.src
  mut failed = false
  for file in (glob **/*.nu) {
    let run = (do -i { ^NU_BIN --ide-check 10 $file } | complete)
    let errors = ($run.stdout | lines | where {|line| $line | str contains '"severity":"Error"' })
    if not ($errors | is-empty) {
      print $"== ($file)"
      print ($errors | str join "\n")
      $failed = true
    }
  }
  if $failed {
    exit 1
  }
  "" | save -f $env.out
}
