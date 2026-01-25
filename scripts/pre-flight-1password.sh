#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight 1Password CLI Check"
echo "==================================="
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
required_version="2.18.0"
SELF_HOST="$(hostname -s 2>/dev/null || hostname)"

for vm in "${VM_LIST[@]}"; do
    echo "=== $vm ==="

    vm_host="${vm#*@}"
    if [[ "$vm_host" == "$SELF_HOST" ]]; then
        echo "📍 Local host detected ($SELF_HOST) — checking locally"

        if ! command -v op >/dev/null 2>&1; then
            echo "❌ op CLI NOT installed"
            echo "   Install: brew install 1password-cli"
            echo
            continue
        fi

        version=$(op --version 2>/dev/null | sed -E 's/[^0-9.]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/' | head -1 || echo '0.0.0')
        if [ "$version" = "0.0.0" ]; then
            echo "⚠️  op CLI installed but version check failed"
        elif [ "$(printf '%s\n' "$required_version" "$version" | sort -V | head -n1)" != "$required_version" ]; then
            echo "❌ op CLI version $version (< $required_version)"
        else
            echo "✅ op CLI version: $version"
        fi

        if op whoami &>/dev/null; then
            echo "✅ op CLI authenticated (account auth)"
        else
            echo "ℹ️  op CLI NOT authenticated (OK - will use service account)"
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

    # Check if op CLI exists
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "command -v op" 2>/dev/null; then
        echo "❌ op CLI NOT installed"
        echo "   Install: brew install 1password-cli"
        echo
        continue
    fi

    # Check version
    version=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "op --version 2>/dev/null | sed -E 's/[^0-9.]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/' | head -1 || echo '0.0.0'")

    if [ "$version" = "0.0.0" ]; then
        echo "⚠️  op CLI installed but version check failed"
        echo "   Manual check: ssh $vm 'op --version'"
    elif [ "$(printf '%s\n' "$required_version" "$version" | sort -V | head -n1)" != "$required_version" ]; then
        echo "❌ op CLI version $version (< $required_version)"
        echo "   Upgrade: brew upgrade 1password-cli"
    else
        echo "✅ op CLI version: $version"

        # Check authentication
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" "op whoami &>/dev/null"; then
            echo "✅ op CLI authenticated (account auth)"
        else
            echo "ℹ️  op CLI NOT authenticated (OK - will use service account)"
        fi
    fi

    echo
done

echo "==================================="
