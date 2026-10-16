#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# The host list comes from the flake rather than a literal: a host added to
# nixosConfigurations is then covered here with no second edit, and a rename
# cannot leave a stale name behind that fails as an eval error nobody reads.
mapfile -t HOSTS < <(
  nix eval --json "$ROOT#nixosConfigurations" --apply builtins.attrNames \
    | tr -d '[]"' | tr ',' '\n' | sort
)

echo "=== format check ==="
nix run "$ROOT#formatter.x86_64-linux" -- --check "$ROOT"

echo ""
echo "=== flake check ==="
# Without --no-build: the flake's checks are the Python lint and the formatter,
# and `--no-build` only evaluated them, so a lint failure never surfaced here.
nix flake check --print-build-logs

echo ""
echo "=== eval check: all hosts ==="
for host in "${HOSTS[@]}"; do
  echo "  eval: $host ..."
  # Force the *toplevel* derivation: that is what walks the unit text, the
  # service configuration and everything else a shallow attribute never reaches.
  # Asking for `system.stateVersion` passed while a wrong key under
  # serviceConfig reached a real rebuild instead - forcing the same expression
  # the build forces is the only eval check worth having. `nix flake check` does
  # not do this either.
  nix eval "$ROOT#nixosConfigurations.$host.config.system.build.toplevel.drvPath" --raw >/dev/null

  hostname="$(nix eval --raw "$ROOT#nixosConfigurations.$host.config.networking.hostName")"
  # Case-insensitive: the attribute is AlexDesktop while that machine's
  # networking.hostName is alex-desktop, and the pairing is legitimate.
  if [[ "${hostname,,}" != "${host,,}" ]]; then
    echo "  ERROR: $host has networking.hostName = '$hostname' (expected '$host')" >&2
    exit 1
  fi
  echo "  hostname: $hostname"
done
echo "  all hosts evaluate OK"

echo "All checks passed."
