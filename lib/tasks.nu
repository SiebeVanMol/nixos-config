# What this repository can do, in one place - and then does it.
#
#   nix run .#tasks                    # pick from a list
#   nix run .#tasks -- --list          # print the list
#   nix run .#tasks -- --json          # the same list, for scripts
#   nix run .#tasks -- <name> [args…]  # run one directly
#
# The list is discovered rather than maintained: every attribute under
# `packages.<system>` is a task (the flake's commands live there), and its
# description comes from the derivation's own `meta.description`. A new helper in
# lib/flake-packages.nix therefore shows up here without an edit - the point being
# that a hand-written menu is a second list that goes stale.
#
# The extras below are the tasks that are not packages, because they act on the
# checkout rather than being a program: the gate, the formatter, the two switch
# paths, and the input update. Anything needing root says so before it runs
# instead of failing halfway through.
#
# Every task runs with its own argv and passes extra arguments straight through,
# so `-- update-overlays --check` reaches the updater's own flag.

# Style constants in one place: `ansi` codes are easy to get subtly wrong, and a
# colour that only appears in one branch looks like an oversight.
const accent = "green_bold"
const dim = "dark_gray"
const warn = "yellow"
const bad = "red_bold"

# Not flake packages. `run` is argv, not a shell string: no word splitting and no
# quoting rules to get wrong.
const extras = [
  {
    name: "test"
    description: "the verification gate: alejandra --check, nix flake check, every host evaluates"
    run: ["./test.sh"]
    root: false
  }
  {
    name: "fmt"
    description: "format the tree with alejandra"
    run: ["nix" "fmt" "."]
    root: false
  }
  {
    name: "switch"
    description: "rebuild and activate this host (Home Manager rides along)"
    run: ["sudo" "nixos-rebuild" "switch" "--flake" "."]
    root: true
  }
  {
    name: "hm-switch"
    description: "activate this user's Home Manager generation only (no root)"
    run: []
    root: false
  }
  {
    name: "flake-update"
    description: "move the inputs (nixpkgs, home-manager, hermes…) to their newest revs"
    run: ["nix" "flake" "update"]
    root: false
  }
  {
    name: "gc"
    description: "collect garbage and drop old generations: nix-collect-garbage -d"
    run: ["nix-collect-garbage" "-d"]
    root: false
  }
]

# Packages whose own description says `sudo nix run`: the *arr export and sweep
# read API keys out of 0700 config files.
const needs_root = ["servarr-export" "servarr-sweep"]

# Exported under `packages` so nix-update has an attribute to rewrite (see
# overlays/update.nu), not to be run: they are server daemons, and starting one
# from a menu is not what exporting them was for. `tasks` excludes itself so the
# menu cannot offer to open itself.
const not_tasks = ["amethyst-mod-manager" "houndarr" "seerrng" "soularr" "tasks"]

def host [] {
  open /proc/sys/kernel/hostname | str trim
}

# The flake's packages with the description each declares. One `nix eval` rather
# than one per package: this runs before the menu, and the menu is not worth four
# seconds.
def discovered [] {
  let meta = (
    ^nix eval --json ".#packages.x86_64-linux" --apply "ps: builtins.mapAttrs (name: p: p.meta.description or \"\") ps"
    | from json
  )
  $meta
  | transpose name description
  | where {|row| not ($row.name in $not_tasks)}
  | each {|row|
    {
      name: $row.name
      description: $row.description
      source: "command"
      # `--` so arguments reach the app rather than nix: `nix run .#x -- --check`.
      run: ["nix" "run" $".#($row.name)" "--"]
      root: ($row.name in $needs_root)
    }
  }
}

# `home-manager switch --flake .#<user>@<host>`: the flake re-exports the
# NixOS-evaluated Home Manager configuration under exactly that attribute, so the
# two names come from the machine this is running on.
def self-attribute [] {
  let user = ($env.USER? | default (do { ^id -un } | str trim))
  $".#($user)@(host)"
}

def tasks [] {
  let self = (self-attribute)
  (discovered)
  | append ($extras | each {|task|
      let task = (
        $task
        | insert source "checkout"
        | upsert run (if $task.name == "hm-switch" { ["home-manager" "switch" "--flake" $self] } else { $task.run })
      )
      $task
    })
  | sort-by name
}

def headline [count: int] {
  $"(ansi $accent)nixos-config(ansi reset)(ansi $dim) · (host) · ($count) tasks(ansi reset)"
}

# Aligned columns, a dim description, and the root marker in yellow: the three
# things that make eleven rows scannable rather than a wall of text.
def row [task: record, width: int] {
  let name = ($task.name | fill --width $width --alignment left)
  let description = (if $task.description == "" { $"(ansi $dim)no description(ansi reset)" } else { $task.description })
  let marker = (if $task.root { $"(ansi $warn)  · sudo(ansi reset)" } else { "" })
  $"  (ansi $accent)($name)(ansi reset)($description)($marker)"
}

def section [title: string, rows: list, width: int] {
  if ($rows | is-empty) {
    return ""
  }
  let body = ($rows | each {|task| row $task $width} | str join (char nl))
  $"\n(ansi $dim)($title)(ansi reset)\n($body)"
}

def as-text [list: list] {
  # Padded to the longest name: `fill` returns the value untouched when it is
  # already longer than the width, which silently collapsed the column.
  let width = (($list | get name | str length | math max) + 2)
  [
    (headline ($list | length))
    (section "commands" ($list | where source == "command") $width)
    (section "checkout" ($list | where source == "checkout") $width)
    ""
    $"(ansi $dim)nix run .#tasks -- <name> [args…]   ·   no argument: pick from a list(ansi reset)"
  ]
  | str join (char nl)
}

def run-task [task: record, rest: list<string>] {
  let argv = ($task.run | append $rest)
  if $task.root {
    print $"(ansi $warn)needs root - sudo will ask for your password(ansi reset)"
  }
  print $"(ansi $dim)→ ($argv | str join ' ')(ansi reset)"
  ^$argv.0 ...($argv | skip 1)
  let code = $env.LAST_EXIT_CODE
  if $code == 0 {
    print $"(ansi $accent)✓(ansi reset) ($task.name)"
  } else {
    print -e $"(ansi $bad)✗(ansi reset) ($task.name): exit ($code)"
    exit $code
  }
}

# `--wrapped`: the flags after a task name belong to *that* task, and without it
# nushell parses `-- tasks update-overlays --check` as an unknown flag of this
# command. `--wrapped` hands them to `$rest` unchanged.
def --wrapped main [
  name?: string # a task name, or --list / --json
  ...rest: string # passed to the task unchanged
  --list (-l) # print the tasks and exit
  --json (-j) # the task list as JSON, for scripts
] {
  # `nix run .#tasks` from a subdirectory would evaluate `.#` there, and every
  # task assumes the checkout root.
  if not ("flake.nix" | path exists) {
    let top = (do { ^git rev-parse --show-toplevel } | complete)
    if $top.exit_code == 0 and ((($top.stdout | str trim) | path join "flake.nix") | path exists) {
      cd ($top.stdout | str trim)
    } else {
      error make {msg: "not inside the flake checkout: no flake.nix here or above"}
    }
  }

  # `$all`, not `$list`: the `--list` flag already binds `$list`, and reusing the
  # name replaced the flag with this table.
  let all = (tasks)

  # `--wrapped` swallows unknown flags into `$rest`, so `--list` and `--json` can
  # arrive as the flag, as the first positional, or as a rest element depending on
  # how the shell split them. All three are accepted rather than one being
  # silently treated as a task name.
  let flags = ($rest | append (if $name == null { [] } else { [$name] }))
  let wants_json = ($json or ($flags | any {|flag| $flag in ["--json" "-j"]}))
  let wants_list = ($list or ($flags | any {|flag| $flag in ["--list" "-l"]}))

  if $wants_json {
    # `print`: a bare `to json` is a value nothing consumes, so with only that
    # pipeline the flag printed nothing at all.
    print ($all | select name source description root run | to json)
    return
  }

  if $wants_list {
    print (as-text $all)
    return
  }

  if $name != null and not ($name | str starts-with "-") {
    let exact = ($all | where name == $name)
    # A prefix is enough when it names one task: typing `rebui` beats being told
    # there is no task called that. Two matches is a question, not a guess.
    let partial = ($all | where {|task| $task.name | str starts-with $name})
    let task = (if ($exact | is-empty) { if ($partial | length) == 1 { $partial | first } } else { $exact | first })
    if $task == null {
      if ($partial | is-empty) {
        print -e $"(ansi $bad)✗(ansi reset) no task named '($name)'"
      } else {
        print -e $"(ansi $bad)✗(ansi reset) '($name)' matches ($partial | get name | str join ', ')"
      }
      print ""
      print (as-text $all)
      exit 1
    }
    run-task $task $rest
    return
  }

  # Interactive: `input list` needs a terminal. Piped or under cron it would
  # otherwise fail with a stack trace, so fall back to printing the list.
  print (headline ($all | length))
  print $"(ansi $dim)type to filter · ↑/↓ to move · enter runs · esc cancels(ansi reset)"
  let chosen = (
    try {
      $all | input list --fuzzy -d {|task|
        let marker = (if $task.root { "  · sudo" } else { "" })
        $"($task.name): ($task.description)($marker)"
      }
    } catch {
      null
    }
  )
  if $chosen == null {
    print ""
    print (as-text $all)
    print ""
    print $"(ansi $dim)no terminal to pick from - run `nix run .#tasks -- <name>`(ansi reset)"
    return
  }
  print ""
  run-task $chosen $rest
}
