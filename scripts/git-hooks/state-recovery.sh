#!/bin/bash
# post-merge/post-checkout hook enforced by agent-skills
# Keeps local environment in sync with remote state.

echo "🔄 [dx-hooks] Checking environment integrity..."

# 1. Beads Import
if [ -f .beads/issues.jsonl ]; then
    # Only import if we have the tool
    if command -v bd &> /dev/null; then
        echo "   📥 Syncing Beads issues..."
        bd import --no-auto-sync 2>/dev/null || true
    fi
fi

# 2. Lockfile Sync (pnpm)
if [ -f pnpm-lock.yaml ]; then
    # Check if lockfile changed in the last operation (HEAD@{1} -> HEAD)
    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q 'pnpm-lock.yaml'; then
        echo "   📦 pnpm-lock.yaml changed. Running pnpm install..."
        if command -v pnpm &> /dev/null; then
            pnpm install --frozen-lockfile >/dev/null 2>&1 || echo "   ⚠️ pnpm install failed. Run manually."
        else
            echo "   ⚠️ pnpm not found. Skipping install."
        fi
    fi
fi

# 3. Lockfile Check (Poetry)
if [ -f poetry.lock ]; then
    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q 'poetry.lock'; then
        echo "   🐍 poetry.lock changed. You may need to run 'poetry install'."
    fi
fi

# 4. Submodule update
if [ -f .gitmodules ]; then
    # Check if submodule pointers changed
    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q 'packages/llm-common'; then
        echo "   🌿 Submodule pointer changed. Updating..."
        git submodule update --init --recursive >/dev/null 2>&1 || echo "   ⚠️ Submodule update failed."
    fi
fi

exit 0