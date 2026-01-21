#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight Network Check"
echo "==========================="
echo

VM_LIST=("epyc6" "macmini" "homedesktop-wsl")

for vm in "${VM_LIST[@]}"; do
    echo "=== $vm ==="

    # Check SSH connectivity
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$vm" "echo 'SSH OK'" 2>/dev/null; then
        echo "✅ SSH reachable"

        # Check if this is localhost
        hostname=$(ssh "$vm" "hostname" 2>/dev/null || echo "unknown")
        current=$(hostname)
        if [ "$hostname" = "$current" ]; then
            echo "ℹ️  This is localhost ($vm)"
        else
            echo "   Remote hostname: $hostname"
        fi
    else
        echo "❌ SSH NOT reachable"
        echo "   Troubleshoot:"
        echo "   1. Check if VM is powered on"
        echo "   2. Check Tailscale: tailscale status"
        echo "   3. Check SSH: ssh -v $vm"
    fi

    echo
done

echo "==========================="
