#!/usr/bin/env bash
# Collects the API keys Homepage's widgets need and writes them as environment
# variables for the homepage-dashboard unit.
#
# Keys are read at runtime from each application's OWN configuration - the same
# rule the rest of this repository follows, because /nix/store is world
# readable and a widget key is as good as a login. That is also why the widget
# YAML in homepage.nix refers to them as {{HOMEPAGE_VAR_*}} placeholders.
#
# Anything not found is reported and skipped: a widget whose key is missing
# shows an error in the dashboard, it does not break the unit.
set -euo pipefail

out="${1:-/run/homepage-dashboard/env}"

mkdir -p "$(dirname "$out")"
umask 077
# systemd reads this file as EnvironmentFile and refuses to start the unit when
# it is absent, so create it before anything that can fail.
: > "$out"

emit() {
  local name="$1" value="${2:-}"
  if [ -z "$value" ]; then
    printf 'homepage-env: no value found for %s\n' "$name" >&2
    return 0
  fi
  printf '%s=%s\n' "$name" "$value" >> "$out"
  printf 'homepage-env: %s supplied\n' "$name"
}

# Servarr applications: the key is an <ApiKey> element in config.xml. Where
# that file lives depends on how the service is started - Prowlarr is launched
# with -data=/var/lib/prowlarr and keeps it directly there, while Sonarr, Radarr
# and Lidarr nest it under .config/<Project> - so both are tried.
xml_key() {
  local dir="$1" file key
  for file in "$dir/config.xml" "$dir"/.config/*/config.xml; do
    [ -f "$file" ] || continue
    key="$(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$file" | head -n 1)"
    if [ -n "$key" ]; then
      printf '%s' "$key"
      return 0
    fi
  done
  return 1
}

for app in sonarr radarr lidarr prowlarr; do
  [ -d "/var/lib/$app" ] || continue
  var="HOMEPAGE_VAR_$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')_KEY"
  if key="$(xml_key "/var/lib/$app")"; then
    emit "$var" "$key"
  else
    emit "$var" ""
  fi
done

# Bazarr keeps its key under [auth] as "apikey", but WHERE depends on version:
# 1.6 moved settings from config.ini to config.yaml and converts an existing
# INI on first start, so both file names and both syntaxes have to be accepted.
# Reading the old INI only is exactly why the Bazarr widget reported an API
# error while every other *arr widget worked.
bazarr_key() {
  local base="${1:-/var/lib/bazarr/config}"
  python3 - "$base/config.yaml" "$base/config.ini" <<'PY'
import re
import sys

# config.yaml holds a dump of the old configparser sections, so the key is
# "apikey: <value>"; config.ini spells it "apikey = <value>".
PATTERNS = (
    r'^\s*apikey\s*:\s*["\']?([^"\'\s#]+)',
    r'^\s*apikey\s*=\s*(\S+)',
)
for path in sys.argv[1:]:
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        continue
    for pattern in PATTERNS:
        match = re.search(pattern, text, re.MULTILINE | re.IGNORECASE)
        if match:
            print(match.group(1).strip())
            raise SystemExit(0)
raise SystemExit(0)
PY
}

emit HOMEPAGE_VAR_BAZARR_KEY "$(bazarr_key)"

# Seerr (and the SeerrNG fork) keep theirs in settings.json under main.apiKey.
if [ -f /var/lib/seerr/settings.json ]; then
  emit HOMEPAGE_VAR_SEERR_KEY \
    "$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("main") or {}).get("apiKey", ""))' /var/lib/seerr/settings.json)"
fi

chmod 600 "$out"
