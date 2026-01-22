#!/bin/bash
set -euo pipefail

echo "╔══════════════════════════════════════════╗"
echo "║  V4.2.1 Pre-Flight Check Suite          ║"
echo "║  Checking all 3 VMs before implementation ║"
echo "╚══════════════════════════════════════════╝"
echo

SCRIPT_DIR="$(dirname "$0")"

# Run all pre-flight checks
"$SCRIPT_DIR/pre-flight-network.sh"
echo
"$SCRIPT_DIR/pre-flight-1password.sh"
echo
"$SCRIPT_DIR/pre-flight-ssh-path.sh"
echo
"$SCRIPT_DIR/pre-flight-ssh-keys.sh"
echo
"$SCRIPT_DIR/pre-flight-ides.sh"
echo
"$SCRIPT_DIR/pre-flight-railway.sh"
echo
"$SCRIPT_DIR/pre-flight-gh-cli.sh"

echo
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ Pre-Flight Checks Complete            ║"
echo "╚══════════════════════════════════════════╝"
echo
echo "Review results above before starting V4.2.1 implementation."
echo
echo "BLOCKERS that must pass:"
echo "  ✓ All 3 VMs reachable via SSH"
echo "  ✓ op CLI >= 2.18.0 installed on all VMs"
echo "  ✓ op CLI in SSH PATH on all VMs"
echo
echo "RECOMMENDED (pass OR document exceptions):"
echo "  ✓ All 4 canonical IDEs installed (see docs/IDE_SPECS.md)"
echo "  ✓ Railway CLI logged in on all VMs"
echo "  ✓ GH CLI logged in on all VMs"
