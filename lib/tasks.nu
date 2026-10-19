# What this repository can do, in one place - and then does it.
#
#   nix run .#tasks                    # numbered menu, then runs the number you type
#   nix run .#tasks -- --list          # the same menu without running anything
#   nix run .#tasks -- --json          # the list for scripts
#   nix run .#tasks -- <name> [args…]  # run one directly, e.g. `-- test`
#
# The list is discovered rather than maintained: every attribute under
# `packages.<system>` is a task (the flake's commands live there), and its
# description comes from the derivation's own `meta.description`. A new helper in
# lib/flake-packages.nix therefore appears here without an edit - the point being
# that a hand-written menu is a second list that goes stale.
#
# The wording in `plain` is the UI. A numbered list, whole sentences, no flag
# names, no task names: someone who has never seen this repository picks a
# number. The technical name and argv are still there for the command line
# (`-- <name>`), and a task with no `plain` entry still appears - with its own
# description, at the bottom - rather than silently vanishing.

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

# How each task is described to a human: what it does in the words someone who
# does not know Nix would use, and where it belongs in the order. Everyday things
# first, consequences last; anything without an entry sorts after these.
const plain = {
  "switch": {
    order: 1
    label: "Apply my configuration"
    note: "rebuilds this machine and switches to it"
    danger: false
  }
  "hm-switch": {
    order: 2
    label: "Apply just my home folder"
    note: "no password; for changes to programs, the shell and desktop settings"
    danger: false
  }
  "test": {
    order: 3
    label: "Check nothing is broken"
    note: "the full verification gate - a minute or three, and the answer is pass or fail"
    danger: false
  }
  "update-overlays": {
    order: 4
    label: "Update the packaged apps"
    note: "asks upstream for newer seerrng, soularr, houndarr and amethyst, then builds them"
    danger: false
  }
  "flake-update": {
    order: 5
    label: "Update nixpkgs and friends"
    note: "moves what everything is built from - run 'Check nothing is broken' afterwards"
    danger: false
  }
  "fmt": {
    order: 6
    label: "Tidy the formatting"
    note: "rewrites files to match the house style; changes no behaviour"
    danger: false
  }
  "servarr-export": {
    order: 7
    label: "Copy the *arr settings into nix"
    note: "a read-only dump you paste into the repo"
    danger: false
  }
  "servarr-sweep": {
    order: 8
    label: "Search the library for better copies"
    note: "slow and rate-limited: the media apps search their indexers"
    danger: false
  }
  "media-recode": {
    order: 9
    label: "Re-encode oversized media"
    note: "a dry run unless you add --apply"
    danger: false
  }
  "rebuild": {
    order: 11
    label: "Rebuild with options"
    note: "the same rebuild, for subcommands like boot or test; the first entry is the everyday one"
    danger: false
  }
  "gc": {
    order: 10
    label: "Free up disk space"
    note: "deletes old system generations and unused packages"
    danger: true
  }
}

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
      $task
      | insert source "checkout"
      | upsert run (if $task.name == "hm-switch" { ["home-manager" "switch" "--flake" $self] } else { $task.run })
    })
  # Ordered for a reader, not alphabetically: the everyday actions first, the
  # irreversible one last, and anything unrecognised after the ones with wording.
  | each {|task|
      let words = ($plain | get -o $task.name | default {})
      $task
      | insert label ($words.label? | default $task.name)
      | insert note ($words.note? | default (if $task.description == "" { "no description yet" } else { $task.description }))
      | insert danger ($words.danger? | default false)
      | insert order ($words.order? | default 90)
    }
  | sort-by order name
}

def headline [count: int] {
  $"(ansi green_bold)nixos-config(ansi reset)(ansi dark_gray) - (host) - ($count) things you can do(ansi reset)"
}

# The menu. Numbers, plain sentences, and one marker where it changes the
# decision: a password prompt, or the fact that it cannot be undone.
def as-text [all: list] {
  let width = (($all | get label | str length | math max) + 2)
  let rows = (
    $all
    | enumerate
    | each {|row|
        let task = $row.item
        let number = (($row.index + 1) | into string | fill --width 3 --alignment right)
        let label = ($task.label | fill --width $width --alignment left)
        let warning = (
          if $task.danger {
            $"(ansi red_bold)  cannot be undone(ansi reset)"
          } else if $task.root {
            $"(ansi yellow)  asks for your password(ansi reset)"
          } else {
            ""
          }
        )
        $"  (ansi green_bold)($number)(ansi reset)  ($label)(ansi dark_gray)($task.note)(ansi reset)($warning)"
      }
  )
  [
    (headline ($all | length))
    ""
    ($rows | str join (char nl))
  ]
  | str join (char nl)
}

def run-task [task: record, rest: list<string>] {
  let argv = ($task.run | append $rest)
  if $task.root {
    print $"(ansi yellow)This needs your password - sudo is about to ask for it.(ansi reset)"
  }
  print ""
  print $"(ansi dark_gray)running: ($argv | str join ' ')(ansi reset)"
  ^$argv.0 ...($argv | skip 1)
  let code = $env.LAST_EXIT_CODE
  if $code == 0 {
    print ""
    print $"(ansi green_bold)Done.(ansi reset) ($task.label)"
  } else {
    print ""
    print -e $"(ansi red_bold)That failed.(ansi reset) ($task.label), exit ($code) - the output above says why."
    exit $code
  }
}

# `--wrapped`: the flags after a task name belong to *that* task, and without it
# nushell parses `-- tasks update-overlays --check` as an unknown flag of this
# command. `--wrapped` hands them to `$rest` unchanged.
def --wrapped main [
  name?: string # a task name, or --list / --json
  ...rest: string # passed to the task unchanged
  --list (-l) # print the menu and exit
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
    print ($all | select name label source description root danger run | to json)
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
        print -e $"(ansi red_bold)There is no task called '($name)'.(ansi reset)"
      } else {
        print -e $"(ansi red_bold)'($name)' could be: ($partial | get name | str join ', ')(ansi reset)"
      }
      print ""
      print (as-text $all)
      exit 1
    }
    run-task $task $rest
    return
  }

  # Interactive: one number, or 0 to leave. It loops instead of exiting on a typo
  # and prints the menu again rather than making the reader scroll.
  print (as-text $all)
  print ""
  loop {
    let answer = (try { input $"(ansi green_bold)Pick a number(ansi reset)(ansi dark_gray), or 0 to quit:(ansi reset) " } catch { null })
    if $answer == null {
      print $"(ansi dark_gray)Nothing to read from here - run `nix run .#tasks -- <name>` instead.(ansi reset)"
      return
    }

    let answer = ($answer | str trim)
    if $answer in ["0" "q" "quit" ""] {
      print "  Nothing done."
      return
    }

    let number = (try { $answer | into int } catch { -1 })
    let chosen = ($all | enumerate | where {|row| ($row.index + 1) == $number} | get item?)
    if ($chosen | is-empty) {
      print -e $"  There is no ($answer). Pick 1 to ($all | length), or 0 to quit."
      continue
    }
    let task = ($chosen | first)

    if $task.danger {
      print $"(ansi red_bold)  This ($task.note).(ansi reset)"
      let confirm = (try { input $"  Type yes to do it, anything else to cancel: " } catch { "" })
      if ($confirm | str trim | str lowercase) != "yes" {
        print "  Cancelled - nothing was done."
        continue
      }
    }

    run-task $task $rest
    return
  }
}
