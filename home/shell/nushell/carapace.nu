# Carapace completions for nushell.
#
# Home Manager's `programs.carapace.enableNushellIntegration` sources whatever
# `carapace _carapace nushell` prints, and carapace 1.7.3 still prints the
# pre-0.116 external completer: a closure declared `{|spans| ...}`. Nushell 0.116
# unified its completer inputs (nushell#18791) so a closure is now handed one
# record — `token`, `place`, `buffer` — and binds the fields it names. The
# legacy positional form still runs, but every shell start prints
# `Positional completer input deprecated`, and that bridge is scheduled for
# removal. So the integration is off and this file is sourced instead: the same
# bridge, declared against the record nushell passes now.
#
# Two things the upstream closure did by hand are gone because nushell does them:
# the alias expansion (`place.command` already carries the expanded command,
# nushell#19085) and the null-guard around `completions.external.completer`,
# which existed for nushell#15654's default and has nothing to protect against
# here — this repository's config.nu is generated whole and nothing else sets a
# completer.
#
# Why this file exists, and when it can go, is in todo.md ("Smaller").

# Carapace picks up completers installed per-user from here. Upstream's snippet
# puts it in front of PATH; the directory is unused today and costs nothing when
# it is missing.
#
# PATH is already a list under nushell's default ENV_CONVERSIONS, so upstream's
# `split row (char esep)` round trip is dropped rather than kept as a no-op.
$env.PATH = (
  $env.PATH
  | where { $in != $"($env.HOME)/.config/carapace/bin" }
  | prepend $"($env.HOME)/.config/carapace/bin"
)

# Part of upstream's bridge, kept as it stands: carapace's nushell documentation
# advertises these three to anything that wants to touch the environment.
def --env get-env [name] { $env | get $name }
def --env set-env [name, value] { load-env { $name: $value } }
def --env unset-env [name] { hide-env $name }

$env.config.completions.external.completer = {|place|
  # Carapace asks the shell what it has so that it does not offer callables the
  # shell cannot run.
  load-env {
    CARAPACE_SHELL_BUILTINS: (help commands | where category != "" | get name | each { split row " " | first } | uniq | str join "\n")
    CARAPACE_SHELL_FUNCTIONS: (help commands | where category == "" | get name | each { split row " " | first } | uniq | str join "\n")
  }

  carapace $place.command.0 nushell ...$place.command
  | from json
}
