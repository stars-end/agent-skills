#!/bin/bash
# feature-lifecycle/start.sh
# Starts a new feature by creating branch and story skeleton.
# Note: Per Beads-only product specs, we no longer auto-create docs/bd-*.md stubs.
# Use 'bd show <id>' to read the authoritative spec from stars-end/bd.

set -e

if [ -z "$1" ]; then
  echo "Usage: start-feature <issue-id>"
  echo "Example: start-feature bd-123"
  exit 1
fi

ISSUE_ID=$1
BRANCH_NAME="feature-${ISSUE_ID}"
STORY_DIR="docs/testing/stories"
STORY_FILE="${STORY_DIR}/story-${ISSUE_ID}.yml"

# 0. Sync current repo before starting work
# Get current repo name
CURRENT_REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
if [[ -n "$CURRENT_REPO" ]]; then
  echo "Syncing $CURRENT_REPO before starting work..."
  if command -v ru >/dev/null 2>&1; then
    ru sync "$CURRENT_REPO" --non-interactive --quiet 2>/dev/null || \
      echo "Warning: sync skipped (dirty tree or error)"
  else
    echo "Warning: ru not found, skipping sync"
  fi
fi

# 1. Create Branch
if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
  echo "⚠️  Branch ${BRANCH_NAME} already exists. Switching..."
  git checkout "${BRANCH_NAME}"
else
  echo "🌿 Creating branch ${BRANCH_NAME}..."
  git checkout -b "${BRANCH_NAME}"
fi

# 2. Read spec from Beads (stars-end/bd is the source of truth)
echo "📋 Reading spec from Beads..."
if command -v bd >/dev/null 2>&1; then
  echo ""
  echo "--- Beads Spec: ${ISSUE_ID} ---"
  bd show "$ISSUE_ID" | head -30
  echo "..."
  echo "Run 'bd show ${ISSUE_ID}' for full spec"
  echo "--------------------------------"
  echo ""
else
  echo "⚠️  Warning: bd CLI not found. Run 'bd show ${ISSUE_ID}' manually."
fi

# 3. Create Story Skeleton (The Guardrail)
if [ ! -f "${STORY_FILE}" ]; then
  echo "🧪 Creating story skeleton: ${STORY_FILE}..."
  mkdir -p "${STORY_DIR}"
  cat > "${STORY_FILE}" <<EOF
name: ${ISSUE_ID} Verification
description: Automated verification for feature ${ISSUE_ID}

steps:
  - name: Login
    path: /login
    action: check_element
    selector: "input[name='email']"

  # TODO: Add specific feature verification steps here
  # - name: Check New Feature
  #   path: /dashboard
  #   ...
EOF
  git add "${STORY_FILE}"
  echo "📝 Created story file. PLEASE EDIT THIS FILE to define 'Done'."
else
  echo "✅ Story file exists: ${STORY_FILE}"
fi

echo ""
echo "🚀 Feature ${ISSUE_ID} started!"
echo "   Branch: ${BRANCH_NAME}"
echo "   Story: ${STORY_FILE}"
echo ""
echo "NEXT STEPS:"
echo "1. Edit ${STORY_FILE} to define success."
echo "2. Run 'bd show ${ISSUE_ID}' for authoritative spec."
echo "3. Run 'sync-feature \"initial setup\"' to save."
