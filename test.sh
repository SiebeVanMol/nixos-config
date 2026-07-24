#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HOSTS=(nixos-desktop nixos-laptop alex-desktop)

echo "=== flake check ==="
nix flake check --no-build --print-build-logs

echo ""
echo "=== eval check: all hosts ==="
for host in "${HOSTS[@]}"; do
  echo "  eval: $host ..."
  nix eval "$ROOT#nixosConfigurations.$host.config.system.stateVersion" --raw
done
echo "  all hosts evaluate OK"


echo "All checks passed."
