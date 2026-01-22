#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight Railway CLI Check"
echo "================================="
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL_TARGETS_SH="$SCRIPT_DIR/canonical-targets.sh"

# shellcheck disable=SC1090
if [ -f "$CANONICAL_TARGETS_SH" ]; then
  source "$CANONICAL_TARGETS_SH"
fi

VM_LIST=()
if declare -p CANONICAL_VMS >/dev/null 2>&1; then
  for entry in "${CANONICAL_VMS[@]}"; do
    VM_LIST+=( "${entry%%:*}" )
  done
fi

# Fallback aliases (if canonical-targets is missing)
if [ "${#VM_LIST[@]}" -eq 0 ]; then
  VM_LIST=( "homedesktop-wsl" "macmini" "epyc6" )
fi

for vm in "${VM_LIST[@]}"; do
    echo "=== $vm ==="

    # First check if SSH works
    if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=2 "$vm" "true" 2>/dev/null; then
        echo "⚠️  SSH unreachable - skipping"
        echo
        continue
    fi

    # Canonical check logic lives in agent-skills/scripts/railway-requirements-check.sh
    # Default to local-dev mode for pre-flight; automated/ci should explicitly set ENV_SOURCES_MODE.
    ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5 "$vm" "ENV_SOURCES_MODE=local-dev ~/agent-skills/scripts/railway-requirements-check.sh --mode local-dev" || true

    echo
done

echo "================================="
