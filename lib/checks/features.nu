# A feature is two halves of one thing: a directory under features/ must carry both,
# and its machine half must be imported by features/default.nix or it never loads.
# Half of a convention going missing quietly is the failure this exists to catch.
def main [] {
  cd $env.src
  let imported = (open features/default.nix)
  mut failed = false

  for dir in (ls features | where type == "dir" | get name) {
    # `ls` returns paths under the store copy, so the directory is shown the way it
    # reads in the repository.
    let name = ($dir | path basename)
    # a half is `half.nix` or a `half/` directory with a default.nix
    for half in ["system" "home"] {
      let flat = ($dir | path join $"($half).nix")
      let nested = ($dir | path join $half "default.nix")
      if not (($flat | path exists) or ($nested | path exists)) {
        print $"features/($name): no ($half).nix - a feature has both halves"
        $failed = true
      }
    }
    if not ($imported | str contains $"./($name)/system.nix") {
      print $"features/($name): not imported by features/default.nix, so it never loads"
      $failed = true
    }
  }

  if $failed {
    exit 1
  }
  "" | save -f $env.out
}
