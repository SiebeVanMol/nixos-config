# Posts a report to the Discord webhook in $ALERT_WEBHOOK_URL.
#
# `monitoring.nix` (the daily health check) and `reclaim.nix` (the weekly disk
# report) each built this by hand: the same 1800-character truncation against
# Discord's 2000-character cap, the same `jq -n --arg content`, the same
# `curl -sfS -X POST` against the same EnvironmentFile. Two copies of a message
# format is two places to get the cap wrong, so it lives here.
#
# Usage: alert-webhook <header>   with the report on stdin.
#
# The header is a line of its own above the report: what the report is, and for
# the health check how many findings it carries. The report is truncated, not
# the header, so the first 1800 characters of a long report are what arrives -
# findings are written most-important-first for that reason.
#
# Exit is always 0. Both callers print the report before calling this, and
# theirs is the exit status that decides whether the unit failed: a webhook that
# is unreachable is a warning in the journal, not a reason to make the report
# look like it did not run. Without a webhook configured the report stays in the
# journal, which is the documented way to run these.
{pkgs}:
pkgs.writeShellApplication {
  name = "alert-webhook";
  runtimeInputs = [pkgs.coreutils pkgs.curl pkgs.jq];
  text = ''
    header="''${1:?usage: alert-webhook <header>, report on stdin}"
    report="$(cat)"

    if [ -z "''${ALERT_WEBHOOK_URL:-}" ]; then
      echo "(ALERT_WEBHOOK_URL unset; journal only)"
      exit 0
    fi

    payload="$header
    ''${report:0:1800}"

    if jq -n --arg content "$payload" '{content: $content}' \
      | curl -sfS -X POST -H 'Content-Type: application/json' \
          --data-binary @- "$ALERT_WEBHOOK_URL" >/dev/null; then
      echo "(alert delivered)"
    else
      echo "WARNING: could not deliver the alert webhook" >&2
    fi
  '';
}
