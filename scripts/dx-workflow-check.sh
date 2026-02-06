#!/usr/bin/env bash
#
# dx-workflow-check.sh
#
# Guardrail for GitHub Actions workflows.
#
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
INVENTORY_FILE="$REPO_ROOT/.github/workflow-inventory.json"
TEMP_INV=$(mktemp)

echo "🔍 Auditing workflows in $REPO_ROOT..."

# Generate fresh inventory
echo '{"workflows": []}' > "$TEMP_INV"

for wf in "$REPO_ROOT"/.github/workflows/*.{yml,yaml}; do
    [ -e "$wf" ] || continue
    name=$(grep "^name:" "$wf" | head -1 | cut -d: -f2- | xargs || basename "$wf")
    path=".github/workflows/$(basename "$wf")"
    
    # Check for dangerous permissions
    if grep -q "permissions: write-all" "$wf"; then
        echo "❌ DANGEROUS: $path uses 'permissions: write-all'"
        exit 1
    fi
    
    # Check for missing permissions block (best effort)
    if ! grep -q "permissions:" "$wf"; then
        echo "⚠️  WARN: $path is missing explicit permissions block"
    fi

    # Update temp inventory
    tmp=$(mktemp)
    jq --arg name "$name" --arg path "$path" \
       '.workflows += [{name: $name, path: $path}]' "$TEMP_INV" > "$tmp" && mv "$tmp" "$TEMP_INV"
done

# Compare with stored inventory
if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "⚠️  $INVENTORY_FILE missing. Creating it..."
    cp "$TEMP_INV" "$INVENTORY_FILE"
    echo "✅ Created $INVENTORY_FILE. Please commit it."
    exit 0
fi

if ! diff -q <(jq -S . "$TEMP_INV") <(jq -S . "$INVENTORY_FILE") >/dev/null; then
    echo "❌ DRIFT: Workflow inventory is out of sync!"
    echo "   Run: scripts/dx-workflow-check.sh --update"
    diff -u <(jq -S . "$INVENTORY_FILE") <(jq -S . "$TEMP_INV") || true
    
    if [[ "${1:-}" == "--update" ]]; then
        cp "$TEMP_INV" "$INVENTORY_FILE"
        echo "✅ Updated $INVENTORY_FILE"
        exit 0
    fi
    exit 1
fi

echo "✅ Workflow inventory is in sync."
rm -f "$TEMP_INV"