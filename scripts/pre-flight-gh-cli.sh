#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight GH CLI Check"
echo "==========================="
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
else
  VM_LIST=( "epyc6" "macmini" "homedesktop-wsl" )
fi

	SELF_HOST="$(hostname -s 2>/dev/null || hostname)"

	for vm in "${VM_LIST[@]}"; do
	    echo "=== $vm ==="

	    vm_host="${vm#*@}"
	    if [[ "$vm_host" == "$SELF_HOST" ]]; then
	        echo "📍 Local host detected ($SELF_HOST) — checking locally"

	        if ! command -v gh >/dev/null 2>&1; then
	            echo "❌ gh CLI NOT installed"
	            echo "   Install: brew install gh"
	            echo
	            continue
	        fi

	        echo "✅ gh CLI installed"
	        if gh auth status &>/dev/null; then
	            echo "✅ gh CLI logged in"
	            gh auth status 2>&1 | head -3 || true
	        else
	            echo "❌ gh CLI NOT logged in"
	            echo "   Fix: gh auth login"
	        fi

	        echo
	        continue
	    fi

	    # First check if SSH works
	    if ! ssh -o BatchMode=yes -o ConnectTimeout=2 "$vm" "true" 2>/dev/null; then
	        echo "⚠️  SSH unreachable - skipping"
	        echo
        continue
    fi

    # Check gh CLI exists
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "command -v gh" 2>/dev/null; then
        echo "❌ gh CLI NOT installed"
        echo "   Install: brew install gh"
        echo
        continue
    fi

    echo "✅ gh CLI installed"

    # Check if logged in
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "gh auth status &>/dev/null"; then
        echo "✅ gh CLI logged in"
        # Show auth status
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "gh auth status 2>&1 | head -3" || true
    else
        echo "❌ gh CLI NOT logged in"
        echo "   Fix: gh auth login"
    fi

    echo
done

echo "==========================="
