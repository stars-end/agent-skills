#!/bin/bash
# scripts/audit-stories.sh
# Audit tool: Find Beads Features missing verification stories.

STORY_DIR="docs/testing/stories"
MISSING=0

echo "🔍 Auditing Beads Features vs Stories..."

# Get all open features from Beads
# Extracting ID from the list (assumes 'bd ready' or similar)
FEATURES=$(bd list --type feature --status open --json | jq -r '.[].id')

for id in $FEATURES; do
    STORY="${STORY_DIR}/story-${id}.yml"
    if [ ! -f "$STORY" ]; then
        echo "❌ MISSING: ${id} has no story at ${STORY}"
        MISSING=$((MISSING+1))
    else
        echo "✅ FOUND: ${id} -> ${STORY}"
    fi
done

if [ $MISSING -gt 0 ]; then
    echo ""
    echo "⚠️  Found $MISSING orphan features. Please create stories using 'start-feature'."
    exit 1
else
    echo ""
    echo "✨ All features have matching stories."
    exit 0
fi

