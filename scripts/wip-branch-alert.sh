#!/usr/bin/env bash
# wip-branch-alert.sh
# Warn when switching to/from WIP auto-checkpoint branches
# Install: ln -sf ~/agent-skills/scripts/wip-branch-alert.sh ~/.git/hooks/post-checkout

set -euo pipefail

PREV_HEAD=$1
PREV_REF=$2
NEW_REF=$3
# 0 = file checkout, 1 = branch checkout
[[ $3 == "0" ]] && exit 0

CURRENT_BRANCH=$(git branch --show-current)

# Check if we're on a WIP auto-checkpoint branch
if [[ "$CURRENT_BRANCH" =~ ^wip/auto/ ]]; then
    echo ""
    echo "⚠️  ═══════════════════════════════════════════════════════════════"
    echo "⚠️  WARNING: You are on a WIP auto-checkpoint branch"
    echo "⚠️  Branch: $CURRENT_BRANCH"
    echo "⚠️  "
    echo "⚠️  Work here is NOT on master/main."
    echo "⚠️  Remember to merge or cherry-pick when ready."
    echo "⚠️  "
    echo "⚠️  To merge to master:"
    echo "⚠️    git checkout master"
    echo "⚠️    git cherry-pick $CURRENT_BRANCH"
    echo "⚠️  ═══════════════════════════════════════════════════════════════"
    echo ""
fi
