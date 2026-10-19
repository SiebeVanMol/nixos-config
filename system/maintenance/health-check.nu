# The daily host health check: failed units, capacity, btrfs errors, SMART, and
# what the *arr services say about themselves.
#
# This was a bash script of awk/grep/sed pipelines inside monitoring.nix. It is
# the tree's rule that scripts are nushell, and this one is entirely parsing -
# which is what `lines`, `split row -r '\s+'`, `where` and `str contains` are for.
# Moving it out of the module's string and into a file is what lets
# `checks.x86_64-linux.nu` parse it: a nushell string inside a .nix file is
# invisible to that check.
#
# The output format is deliberately unchanged - the webhook header, the journal
# and the "all clear" line are what the rest of the system reads.
#
# The placeholders are substituted at build time by monitoring.nix:
#   PATH_FROM_NIX  store paths of the tools this shells out to
#   MOUNTS_JSON    the btrfs mounts to watch, from config.fileSystems
#   ARR_HEALTH     the binary that reports the *arr services' own warnings
#   ALERT_WEBHOOK  the shared Discord client (lib/alert-webhook.nix)
#
# split row, because a colon-joined makeBinPath string is one PATH element.
$env.PATH = (("PATH_FROM_NIX" | split row ":") ++ $env.PATH)

const arrHealth = "ARR_HEALTH"
const alertWebhook = "ALERT_WEBHOOK"

# Columns are padded, so `split row ' '` would return empty fields for runs of
# spaces; awk's default behaviour is what is wanted here.
def fields [line: string] {
  $line | split row -r '\s+' | where {|field| $field != ""}
}

# stdout of a finished command as lines, empty when the command failed. The bash
# version carried `2>/dev/null || true` on every call: btrfs and smartctl need
# root, lsblk lists types a host may not have, and none of that is a finding of
# its own.
# `$in`, not a parameter: every caller pipes `... | complete` into it, and a
# declared parameter would require the value as an argument instead.
def stdout-lines [] {
  $in.stdout? | default "" | lines
}

def main [] {
  # `let`, not `const`: parsing the substituted JSON is a command, and const
  # bindings only hold values the parser can compute.
  let mounts = ("MOUNTS_JSON" | from json)

  mut findings: list<string> = []
  # A critical finding is something already broken or about to be: the unit
  # fails, so it shows in `systemctl --failed`. Warnings log and webhook but
  # leave the unit green, because a check that turns red daily for something
  # merely worth knowing is one nobody reads.
  mut critical = false

  # 1. Services that are not running. Dependants of a dead service usually fail
  #    too, so one root cause shows up as several lines here. This unit excludes
  #    itself so its own failure does not cascade.
  let failed = (
    ^systemctl list-units --state=failed --no-legend --plain
    | complete
    | stdout-lines
    | each {|line| fields $line | first }
    | where {|unit| $unit != null and not ($unit | str starts-with "nixos-health-check")}
  )
  if ($failed | is-not-empty) {
    $findings = ($findings | append "failed systemd units:")
    for unit in $failed {
      $findings = ($findings | append $"  ($unit)")
    }
    $critical = true
  }

  for mount in $mounts {
    if not ($mount | path exists) {
      continue
    }

    # 2. Capacity. 95% leaves no room for a large import; 90% is the point to
    #    start pruning.
    let pct = (
      try {
        ^df --output=pcent $mount
        | complete
        | stdout-lines
        | last
        | str trim
        | str replace "%" ""
        | into int
      } catch { null }
    )
    if $pct != null {
      if $pct >= 95 {
        $findings = ($findings | append $"CRITICAL: ($mount) is ($pct)% full")
        $critical = true
      } else if $pct >= 90 {
        $findings = ($findings | append $"warning: ($mount) is ($pct)% full")
      }
    }

    # 3. btrfs per-device error counters. A non-zero counter means the kernel
    #    already saw IO it could not fix.
    let errors = (
      ^btrfs device stats $mount
      | complete
      | stdout-lines
      | where {|line| (fields $line | last) != "0"}
    )
    if ($errors | is-not-empty) {
      $findings = ($findings | append $"CRITICAL: btrfs device errors on ($mount):")
      for line in $errors {
        $findings = ($findings | append $"  ($line)")
      }
      $critical = true
    }
  }

  # 4. SMART overall health, one line per physical disk. Devices that do not
  #    report a health line (USB bridges, virtual disks) are skipped rather than
  #    reported as failures.
  let disks = (
    ^lsblk -dno "NAME,TYPE"
    | complete
    | stdout-lines
    | each {|line| fields $line}
    | where {|row| ($row | length) >= 2 and $row.1 == "disk"}
    | each {|row| $row.0}
  )
  for disk in $disks {
    let health = (
      ^smartctl -H $"/dev/($disk)"
      | complete
      | stdout-lines
      | where {|line| $line | str contains "self-assessment test result:"}
      | first
      | default ""
      | split row "result:"
      | last
      | str trim
    )
    if $health == "" {
      continue
    }
    if not ($health | str starts-with "PASSED") and $health != "OK" {
      $findings = ($findings | append $"CRITICAL: SMART health on /dev/($disk): ($health)")
      $critical = true
    }
  }

  # 5. The *arr services' own health warnings: an indexer that started refusing
  #    connections, a download client that went away, a root folder that is no
  #    longer writable. Each application already knows this and exposes it on
  #    /api/<v>/health; without this the only way to learn about it is to open
  #    four web UIs and look. Warnings, not critical: the stack still plays and
  #    still imports.
  for line in (^$arrHealth | complete | stdout-lines) {
    if ($line | str trim) != "" {
      $findings = ($findings | append $line)
    }
  }

  if ($findings | is-empty) {
    print "nixos health check: all clear"
    return
  }

  let host = (open /proc/sys/kernel/hostname | str trim)
  let count = ($findings | length)
  # `finding(s)` in a variable: inside a `$"..."` string the `(s)` would be read
  # as a subexpression, which is how this first failed with "external command".
  let noun = "finding(s)"
  let report = ($findings | str join (char nl))
  print $"=== nixos health check: ($count) ($noun) ==="
  print $report

  # Delivery is shared with the weekly disk report; lib/alert-webhook.nix owns
  # the truncation against Discord's cap and the "a failed webhook is a warning,
  # not a failed report" rule.
  $report | ^$alertWebhook $"($host): ($count) health ($noun)"

  # Only a critical finding fails the unit; warnings are reported and delivered
  # but leave `systemctl --failed` clean.
  if $critical {
    exit 1
  }
}
