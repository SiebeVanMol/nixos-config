# Update the overlay pins.
#
# `overlays/` carries four packages nixpkgs does not. Each is a `version` and a
# `hash` inside its file, and nothing was watching either: a pin could sit a
# year behind upstream and the only sign would be whatever the app's own UI
# said. The gap here was not hypothetical - seerrng is pinned at 3.19.3 while
# upstream's newest tag is 3.67.0.
#
# `--check` asks upstream for the newest version of each and compares it with
# the pin. It changes nothing and exits non-zero when something is behind, which
# is what the weekly timer runs (system/maintenance/overlays.nix).
#
# Without `--check` the pins that are behind are updated, and each updated
# package is built before the script calls it done. Two of the four can be
# updated mechanically (`how = "nix-update"`: it rewrites the version and
# recomputes the hash); two cannot, and they say why rather than pretending:
#
#   - amethyst ships an AppImage whose URL contains the version, and its
#     derivation has no `position` for nix-update to rewrite, so version, URL
#     and hash are edited by hand.
#   - soularr is pinned to a bare commit (`unstable-<date>`) but upstream now
#     tags releases, so moving it is a change of fetch shape, not a bump.
#
# A mechanical update can still fail - seerrng's newest release wants Node 24
# while the overlay pins nodejs-slim_22, and its `pnpmDeps` hash moves with the
# lockfile - so the build is part of the update, not an afterthought. A failure
# puts the file back as it was and reports what broke.
#
# What this cannot update at all: the vendored dependencies inside the overlays
# (aiosqlite and aiosqlitepool in houndarr, slskd-api in soularr) are wheels
# pinned to the Python version their upstream supports, not releases of the
# package the file is named after. They move when the package needs them.
#
# Run from the repository root: `nix run .#update-overlays [-- --check]`, which
# is the wrapper in lib/flake-packages.nix with nix, nix-update and git on PATH.
#
# `PATH_FROM_NIX` below is that wrapper's placeholder, replaced at build time
# with the store paths of those three. Prepending it here rather than wrapping
# the program in bash keeps the script the only thing that has to be read.
#
# split row, because the placeholder is a colon-joined makeBinPath string and a
# single PATH element containing colons resolves nothing.
$env.PATH = (("PATH_FROM_NIX" | split row ":") ++ $env.PATH)

const pins = [
  {
    attr: "seerrng"
    file: "overlays/seerrng.nix"
    repo: "snapetech/seerrng"
    kind: "tags"
    how: "nix-update"
  }
  {
    attr: "soularr"
    file: "overlays/soularr.nix"
    repo: "mrusse/soularr"
    kind: "tags"
    how: "nix-update"
  }
  {
    attr: "houndarr"
    file: "overlays/houndarr.nix"
    repo: "av1155/houndarr"
    kind: "tags"
    how: "nix-update"
  }
  {
    attr: "amethyst-mod-manager"
    file: "overlays/amethyst-mod-manager.nix"
    repo: "ChrisDKN/Amethyst-Mod-Manager"
    kind: "releases"
    how: "manual"
    manual: "AppImage: edit version, URL and hash by hand (nix store prefetch-file <url>)"
  }
]

# Tags sort as strings by default, which puts 1.9.0 above 1.13.3 - so each
# segment is zero-padded to six digits and the padded form is what is compared.
# Non-numeric segments (a `-beta` suffix) would sort oddly; the tag filter above
# drops anything that is not a plain dotted version.
def version-key [version: string] {
  $version | split row "." | each {|part| $part | fill --width 6 --alignment right --character "0"} | str join "."
}

# GitHub's releases, tags and commits endpoints, condensed to the newest version
# string. A bare checkout has no version of its own, so it is described by the
# date of its newest commit - the shape its pin already has.
def newest [pin: record] {
  let base = $"https://api.github.com/repos/($pin.repo)"
  let headers = {
    Accept: "application/vnd.github+json"
    "User-Agent": "nixos-config-overlay-updater"
  }
  match $pin.kind {
    "releases" => (http get --headers $headers $"($base)/releases/latest" | get tag_name | str trim -c "v")
    "tags" => (
      http get --headers $headers $"($base)/tags"
      | get name
      | each {|tag| $tag | str trim -c "v"}
      | where {|v| $v =~ '^[0-9]+(\.[0-9]+)+$'}
      | sort-by {|v| version-key $v}
      | last
    )
    "commits" => (
      http get --headers $headers $"($base)/commits?per_page=1"
      | first
      | get commit
      | get author
      | get date
      | str substring 0..9
      | $"unstable-($in)"
    )
  }
}

# The version the overlay currently pins, read out of the flake rather than
# parsed out of the file: the four files spell `version` differently (a `let`
# binding, an overrideAttrs attr, one derivation without a version attr at all)
# and a regex over them would be a second source of truth that goes stale
# silently. The derivation name always carries it - `<attr>-<version>`.
def pinned [attr: string] {
  let name = (^nix eval --raw $".#packages.x86_64-linux.($attr).name")
  $name | str substring ($attr | str length | $in + 1)..
}

# The last line that names a failure, else the last non-empty one: nix-update
# reports through a Python traceback, whose final line is `nix log ...` when the
# actual cause (a hash it could not prefetch) is two lines above.
def last-line [text: string] {
  let lines = ($text | lines | where {|line| ($line | str trim) != ""})
  let named = ($lines | where {|line| $line =~ '(?i)(error|failed)'} | last)
  if $named == null { $lines | last } else { $named | str trim }
}

def main [
  --check (-c)  # Report only; change nothing
] {
  let rows = ($pins | each {|pin|
    let current = (pinned $pin.attr)
    let latest = (newest $pin)
    {
      package: $pin.attr
      pinned: $current
      latest: $latest
      state: (if $current == $latest { "current" } else { "BEHIND" })
      how: $pin.how
    }
  })

  print ($rows | select package pinned latest state how | to text)

  let behind = ($rows | where state == "BEHIND")
  if ($behind | is-empty) {
    return
  }
  if $check {
    error make {
      msg: $"($behind | length) overlay pins behind upstream"
      label: {text: "run without --check to update what can be updated", span: (metadata $check).span}
    }
  }

  mut needs_a_hand = []
  mut broken = []
  for row in $behind {
    let pin = ($pins | where attr == $row.package | first)
    if $pin.how == "manual" {
      print $"($pin.attr): ($row.pinned) -> ($row.latest) needs a hand - ($pin.manual)"
      $needs_a_hand = ($needs_a_hand | append $pin.attr)
      continue
    }
    print $"($pin.attr): ($row.pinned) -> ($row.latest) via nix-update"
    let bumped = (do { ^nix-update --flake $pin.attr } | complete)
    if $bumped.exit_code != 0 {
      # nix-update can fail after writing the version (a hash it cannot prefetch
      # leaves the file half-bumped), so the file goes back either way.
      ^git checkout -- $pin.file
      print -e $"  nix-update failed, reverted ($pin.file): (last-line $bumped.stderr)"
      $broken = ($broken | append $pin.attr)
      continue
    }
    let built = (do { ^nix build --no-link $".#packages.x86_64-linux.($pin.attr)" } | complete)
    if $built.exit_code != 0 {
      # The bump is unproven, so it does not stay: an unbuildable pin in the
      # tree is worse than a stale one.
      ^git checkout -- $pin.file
      print -e $"  built from ($row.pinned) but not from ($row.latest) - reverted ($pin.file)"
      print -e $"  (last-line $built.stderr)"
      $broken = ($broken | append $pin.attr)
      continue
    }
    print $"  ok: ($pin.attr) ($row.latest) builds"
  }

  print ""
  if ($needs_a_hand | is-empty) and ($broken | is-empty) {
    print "all behind pins updated - the diff is uncommitted on purpose: run ./test.sh, then commit"
    return
  }
  if not ($needs_a_hand | is-empty) {
    print $"by hand: ($needs_a_hand | str join ', ')"
  }
  if not ($broken | is-empty) {
    print $"failed:  ($broken | str join ', ')"
  }
  error make {msg: "not every pin could be updated"}
}
