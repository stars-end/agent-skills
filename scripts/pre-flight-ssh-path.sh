#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight SSH PATH Check"
echo "=============================="
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
	        export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

	        if command -v op >/dev/null 2>&1; then
	            echo "✅ op CLI in PATH"
	            echo "   PATH: $PATH"
	        else
	            echo "❌ op CLI NOT in PATH"
	        fi

	        if [ -d ~/.agent/skills ]; then
	            echo "✅ ~/.agent/skills exists"
	        else
	            echo "⚠️  ~/.agent/skills NOT found (will be created)"
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

    # Check if op CLI is in SSH PATH
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "command -v op" 2>/dev/null; then
        echo "✅ op CLI in SSH PATH"

        # Show SSH PATH
        ssh_path=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "echo \$PATH" 2>/dev/null)
        echo "   SSH PATH: $ssh_path"
    else
        echo "❌ op CLI NOT in SSH PATH"

        # Show SSH PATH for debugging
        ssh_path=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "echo \$PATH" 2>/dev/null || echo "unable to determine")
        echo "   SSH PATH: $ssh_path"
        echo ""
        echo "   Fix: Add to ~/.zshenv (NOT ~/.zshrc):"
        echo '   export PATH="/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/opt/homebrew/bin:$PATH"'
    fi

    # Check if ~/.agent/skills exists
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "[ -d ~/.agent/skills ]" 2>/dev/null; then
        echo "✅ ~/.agent/skills exists"
    else
        echo "⚠️  ~/.agent/skills NOT found (will be created)"
    fi

    echo
done

echo "=============================="
