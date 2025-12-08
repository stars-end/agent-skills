#!/usr/bin/env bash
# check-drift.sh - Check if repo's workflows drift from agent-skills templates

set -euo pipefail

AGENT_SKILLS="${HOME}/.agent/skills"
TARGET_REPO="${1:-.}"

echo "🔍 Checking workflow template drift..."
echo ""
echo "Agent-skills: $AGENT_SKILLS"
echo "Target repo:  $TARGET_REPO"
echo ""

if [ ! -d "$AGENT_SKILLS/github-actions/workflows" ]; then
  echo "❌ agent-skills not found at $AGENT_SKILLS"
  echo "Run: cd ~/.agent/skills && git pull"
  exit 1
fi

if [ ! -d "$TARGET_REPO/.github/workflows" ]; then
  echo "⚠️  No workflows found in $TARGET_REPO/.github/workflows"
  echo "Nothing to check"
  exit 0
fi

TEMPLATES=(
  "lockfile-validation.yml"
  "python-test-job.yml"
  "dx-auditor.yml"
)

DRIFTED=0

for template in "${TEMPLATES[@]}"; do
  REF_FILE="$AGENT_SKILLS/github-actions/workflows/${template}.ref"
  TARGET_FILE="$TARGET_REPO/.github/workflows/$template"

  if [ ! -f "$REF_FILE" ]; then
    echo "⚠️  Template not found: $template.ref (skipping)"
    continue
  fi

  if [ ! -f "$TARGET_FILE" ]; then
    echo "⚠️  Workflow not deployed: $template (skipping)"
    continue
  fi

  # Compare files (ignoring comments and whitespace)
  if diff -w -B \
       <(grep -v '^#' "$REF_FILE" | grep -v '^[[:space:]]*$') \
       <(grep -v '^#' "$TARGET_FILE" | grep -v '^[[:space:]]*$') \
       > /dev/null 2>&1; then
    echo "✅ $template - in sync"
  else
    echo "❌ $template - DRIFT DETECTED"
    echo "   Reference: $REF_FILE"
    echo "   Target:    $TARGET_FILE"
    echo ""
    echo "   To see diff:"
    echo "   diff $REF_FILE $TARGET_FILE"
    echo ""
    DRIFTED=$((DRIFTED + 1))
  fi
done

echo ""
if [ $DRIFTED -eq 0 ]; then
  echo "✅ All workflows in sync with agent-skills templates"
  exit 0
else
  echo "⚠️  $DRIFTED workflow(s) have drift"
  echo ""
  echo "To sync:"
  echo "  ~/.agent/skills/deployment/sync-to-repo.sh $TARGET_REPO"
  exit 1
fi
