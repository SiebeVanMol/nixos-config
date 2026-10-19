# What this repository can do, in one place - and then does it.
#
#   nix run .#tasks                    # pick from a list
#   nix run .#tasks -- --list          # just print the list
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
# paths, and the input update. Anything needing root says so in the list instead
# of failing halfway through.
#
# Every task runs with its own argv and passes extra arguments straight through,
# so `-- update-overlays --check` reaches the updater's own flag.

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
    description: "rebuild and activate this host (sudo; Home Manager rides along)"
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
  let host = (open /proc/sys/kernel/hostname | str trim)
  $".#($user)@($host)"
}

def tasks [] {
  let self = (self-attribute)
  (discovered)
  | append ($extras | each {|task|
      if $task.name == "hm-switch" {
        $task | upsert run ["home-manager" "switch" "--flake" $self]
      } else {
        $task
      }
    })
  | sort-by name
}

# A plain aligned list rather than a table: `input list` draws its own frame, and
# this is what gets printed when there is no terminal to pick from.
def as-text [list: list] {
  # Padded to the longest name: `fill` returns the value untouched when it is
  # already longer than the width, which silently collapsed the column.
  let width = (($list | get name | str length | math max) + 2)
  $list
  | each {|task|
    let name = ($task.name | fill --width $width --alignment left)
    let note = (if $task.root { "  [needs root]" } else { "" })
    $"  ($name)($task.description)($note)"
  }
  | str join (char nl)
}

def run-task [task: record, rest: list<string>] {
  let argv = ($task.run | append $rest)
  print $"running: ($argv | str join ' ')"
  ^$argv.0 ...($argv | skip 1)
  let code = $env.LAST_EXIT_CODE
  if $code != 0 {
    print -e $"($task.name): exit ($code)"
    exit $code
  }
}

# `--wrapped`: the flags after a task name belong to *that* task, and without it
# nushell parses `-- tasks update-overlays --check` as an unknown flag of this
# command. `--wrapped` hands them to `$rest` unchanged.
def --wrapped main [
  name?: string # a task name, or --list
  ...rest: string # passed to the task unchanged
  --list (-l) # print the tasks and exit
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

  if $list or ($name == "--list") {
    print (as-text $all)
    print ""
    print "nix run .#tasks -- <name> [args…]    (or no argument, to pick from a list)"
    return
  }

  if $name != null {
    let task = ($all | where name == $name | first)
    if $task == null {
      print -e $"no task named '($name)'"
      print (as-text $all)
      exit 1
    }
    run-task $task $rest
    return
  }

  # Interactive: `input list` needs a terminal. Piped or under cron it would
  # otherwise fail with a stack trace, so fall back to printing the list.
  let chosen = (
    try {
      $all | input list --fuzzy -d {|task| $"($task.name): ($task.description)"}
    } catch {
      null
    }
  )
  if $chosen == null {
    print (as-text $all)
    print ""
    print "no terminal to pick from - run `nix run .#tasks -- <name>`"
    return
  }
  run-task $chosen $rest
}
