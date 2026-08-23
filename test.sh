#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HOSTS=(nixos-desktop nixos-laptop alex-desktop)

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
  if [[ "$hostname" != "$host" ]]; then
    echo "  ERROR: $host has networking.hostName = '$hostname' (expected '$host')" >&2
    exit 1
  fi
  echo "  hostname: $hostname"
done
echo "  all hosts evaluate OK"


echo "All checks passed."
