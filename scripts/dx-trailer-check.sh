#!/usr/bin/env bash
#
# dx-trailer-check.sh
#
# Enforces commit trailers on agent branches.
#
set -euo pipefail

# Required trailers
REQUIRED=(
    "Feature-Key"
    "Agent"
    "Role"
)

BRANCH=$(git branch --show-current)

# Agent branch patterns
AGENT_PATTERNS=("codex/" "auto-checkpoint/" "bd-" "rescue-" "feature-" "v7.8-")

is_agent_branch() {
    for p in "${AGENT_PATTERNS[@]}"; do
        if [[ "$BRANCH" == "$p"* ]]; then
            return 0
        fi
    done
    return 1
}

if ! is_agent_branch; then
    # Not an agent branch, skip enforcement (human mode)
    exit 0
fi

echo "🔍 Checking agent branch commit trailers: $BRANCH"

# Check last 5 commits on this branch
COMMITS=$(git rev-list --max-count=5 HEAD)

for commit in $COMMITS; do
    msg=$(git log -1 --pretty=format:%B "$commit")
    
    for trailer in "${REQUIRED[@]}"; do
        if ! echo "$msg" | grep -qi "^$trailer:"; then
            echo "⚠️  WARN: Commit $commit is missing '$trailer:' trailer"
            # In V7.8 we only warn, we do not exit 1 yet to avoid blocking workflow
        fi
    done
done

echo "✅ Trailer check complete (warn-only)."
