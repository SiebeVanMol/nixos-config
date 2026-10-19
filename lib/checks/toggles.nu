# Every feature module declares its own toggle (`options.device.<area>.<stem>.enable`),
# so the option is greppable in the file that owns it instead of being generated from
# the file name by a metaprogram. Modules that are deliberately unconditional declare
# none and are listed here, which makes adding one a deliberate edit rather than the
# consequence of forgetting a line.
const unconditional = [
  "system/security/web-jails.nix"
  "system/wm/fonts.nix"
  "system/wm/pipewire.nix"
  "system/wm/wayland.nix"
]

def main [] {
  cd $env.src
  mut failed = false

  for area in ["app" "hardware" "security" "wm"] {
    for file in (glob $"system/($area)/*.nix") {
      # `glob` hands back paths relative to the store path we cd'd into, so the
      # unconditional list - which is written relative to the repository - has to be
      # compared against a relative path, and the message should name one too.
      let rel = ($file | path relative-to $env.src)
      let stem = ($file | path basename | str replace --all ".nix" "")
      let needle = $"options.device.($area).($stem).enable"
      if (open $file | str contains $needle) { continue }
      if ($rel in $unconditional) { continue }
      print -e $"($rel) declares no toggle and is not on the unconditional list"
      print -e $"either add ($needle) or name the file in that list"
      $failed = true
    }
  }

  if $failed {
    exit 1
  }
  "" | save -f $env.out
}
