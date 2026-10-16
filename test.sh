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
nix flake check --no-build --print-build-logs

echo ""
echo "=== eval check: all hosts ==="
for host in "${HOSTS[@]}"; do
  echo "  eval: $host ..."
  nix eval "$ROOT#nixosConfigurations.$host.config.system.stateVersion" --raw >/dev/null

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
