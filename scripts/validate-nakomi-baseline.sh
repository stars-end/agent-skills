#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
AGENTS_FILE="$REPO_ROOT/AGENTS.md"
BASELINE_FILE="$REPO_ROOT/dist/universal-baseline.md"

require_line() {
  local target="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$target"; then
    echo "missing required Nakomi content in $target: $pattern" >&2
    exit 1
  fi
}

for target in "$AGENTS_FILE" "$BASELINE_FILE"; do
  require_line "$target" "## Founder Cognitive Load Policy (Binary)"
  require_line "$target" "## Long-Term Payoff Bias"
  require_line "$target" "No burn-in, phased cutover, transition periods, or dual-path rollouts in dev/staging."
done

echo "Nakomi baseline validation passed"
