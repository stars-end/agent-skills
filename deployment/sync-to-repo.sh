#!/usr/bin/env bash
# sync-to-repo.sh - Sync agent-skills templates to target repo

set -euo pipefail

AGENT_SKILLS="${HOME}/.agent/skills"
TARGET_REPO="${1:-.}"

if [ "$TARGET_REPO" = "." ]; then
  echo "❌ Must specify target repo"
  echo ""
  echo "Usage:"
  echo "  $0 /path/to/repo"
  echo ""
  echo "Example:"
  echo "  $0 ~/prime-radiant-ai"
  exit 1
fi

echo "🔄 Syncing agent-skills templates to $TARGET_REPO"
echo ""

if [ ! -d "$AGENT_SKILLS/github-actions/workflows" ]; then
  echo "❌ agent-skills not found at $AGENT_SKILLS"
  echo "Run: cd ~/.agent/skills && git pull"
  exit 1
fi

if [ ! -d "$TARGET_REPO" ]; then
  echo "❌ Target repo not found: $TARGET_REPO"
  exit 1
fi

mkdir -p "$TARGET_REPO/.github/workflows"

TEMPLATES=(
  "lockfile-validation.yml"
  "python-test-job.yml"
  "dx-auditor.yml"
)

echo "Available templates:"
for template in "${TEMPLATES[@]}"; do
  echo "  - $template"
done
echo ""

read -p "Select templates to sync (comma-separated, or 'all'): " SELECTION

if [ "$SELECTION" = "all" ]; then
  SELECTED_TEMPLATES=("${TEMPLATES[@]}")
else
  IFS=',' read -ra SELECTED_TEMPLATES <<< "$SELECTION"
fi

SYNCED=0

for template in "${SELECTED_TEMPLATES[@]}"; do
  template=$(echo "$template" | xargs)  # Trim whitespace

  REF_FILE="$AGENT_SKILLS/github-actions/workflows/${template}.ref"
  TARGET_FILE="$TARGET_REPO/.github/workflows/$template"

  if [ ! -f "$REF_FILE" ]; then
    echo "⚠️  Template not found: $template.ref (skipping)"
    continue
  fi

  # Check if target exists and show diff
  if [ -f "$TARGET_FILE" ]; then
    echo "⚠️  $template already exists in target repo"
    echo ""
    echo "Diff:"
    diff -u "$TARGET_FILE" "$REF_FILE" || true
    echo ""
    read -p "Overwrite? (y/N): " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
      echo "Skipping $template"
      continue
    fi
  fi

  # Copy template (remove .ref extension)
  cp "$REF_FILE" "$TARGET_FILE"
  echo "✅ Synced: $template"
  SYNCED=$((SYNCED + 1))
done

echo ""
if [ $SYNCED -eq 0 ]; then
  echo "⚠️  No templates synced"
  exit 0
else
  echo "✅ Synced $SYNCED template(s) to $TARGET_REPO"
  echo ""
  echo "Next steps:"
  echo "  cd $TARGET_REPO"
  echo "  git status"
  echo "  git add .github/workflows/"
  echo "  git commit -m 'ci: Sync workflow templates from agent-skills'"
  exit 0
fi
