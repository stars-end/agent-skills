#!/bin/bash
# pre-commit hook enforced by agent-skills
# Ensures scripts are executable.

echo "🔍 [dx-hooks] Checking script permissions..."

# Find modified shell scripts and make them executable
git diff --cached --name-only --diff-filter=ACM | grep -E '\.(sh|py)$' | xargs -I {} chmod +x {} 2>/dev/null || true
git add . 2>/dev/null || true

exit 0

