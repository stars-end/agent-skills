#!/bin/bash
echo "🔄 [dx-hooks] Checking environment integrity..."

# Compatibility-only Beads import hook. In active Dolt-only workflows this is
# disabled unless explicitly enabled by BEADS_LEGACY_JSONL_IMPORT=1.
if [[ "${BEADS_LEGACY_JSONL_IMPORT:-0}" == "1" ]] && [ -f .beads/issues.jsonl ] && command -v bd &> /dev/null; then
    # Attempt import, ignore errors (safe default)
    bd import 2>/dev/null || true
elif [[ "${BEADS_LEGACY_JSONL_IMPORT:-0}" != "1" ]] && [ -f .beads/issues.jsonl ]; then
    echo "⚠️ Legacy Beads JSONL file detected; import skipped in active contract."
    echo "   Set BEADS_LEGACY_JSONL_IMPORT=1 to run explicit compatibility import."
fi
if [ -f pnpm-lock.yaml ] && command -v pnpm &> /dev/null; then
    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q "pnpm-lock.yaml"; then
        echo "🔄 [dx] pnpm-lock changed. Installing..."
        pnpm install --frozen-lockfile >/dev/null 2>&1 || echo "⚠️ pnpm install failed."
    fi
fi
if [ -f .gitmodules ]; then
    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q "packages/llm-common"; then
        echo "🔄 [dx] Submodules changed. Updating..."
        git submodule update --init --recursive >/dev/null 2>&1 || true
    fi
fi
exit 0
