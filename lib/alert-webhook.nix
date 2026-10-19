# Posts a report to the Discord webhook in $ALERT_WEBHOOK_URL.
#
# `monitoring.nix` (the daily health check) and `reclaim.nix` (the weekly disk
# report) each built this by hand: the same 1800-character truncation against
# Discord's 2000-character cap, the same JSON envelope, the same POST against the
# same EnvironmentFile. Two copies of a message format is two places to get the
# cap wrong, so it lives here - and written in nushell it needs neither jq nor
# curl: `to json` and `http post` are the shell.
#
# Usage: alert-webhook <header>   with the report on stdin.
#
# The header is a line of its own above the report: what the report is, and for
# the health check how many findings it carries. The report is truncated, not the
# header, so the first 1800 characters of a long report are what arrives -
# findings are written most-important-first for that reason.
#
# Exit is always 0. Both callers print the report before calling this, and
# theirs is the exit status that decides whether the unit failed: a webhook that
# is unreachable is a warning in the journal, not a reason to make the report
# look like it did not run. Without a webhook configured the report stays in the
# journal, which is the documented way to run these.
{pkgs}:
pkgs.writers.writeNuBin "alert-webhook" ''
  def main [header: string] {
    # The callers send the report with a trailing newline; `$(cat)` used to drop
    # it, and the payload should not carry it either.
    let report = (open --raw /dev/stdin | str trim --right)

    let url = ($env.ALERT_WEBHOOK_URL? | default "")
    if ($url | is-empty) {
      print "(ALERT_WEBHOOK_URL unset; journal only)"
      return
    }

    # Discord caps message content at 2000 characters; the header line counts,
    # so the report keeps 1800 of them (`0..<1800` is exclusive, i.e. exactly
    # 1800 characters; `0..1800` would be 1801). `str substring` clamps to the
    # length of a shorter report.
    let payload = ([$header ($report | str substring 0..<1800)] | str join (char nl))

    try {
      http post $url ({content: $payload} | to json) --content-type "application/json" | ignore
      print "(alert delivered)"
    } catch {
      print -e "WARNING: could not deliver the alert webhook"
    }
  }
''
