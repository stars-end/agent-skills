#!/usr/bin/env bash
# check-derived-freshness.sh
# Deterministic guard: fail when committed derived artifacts are stale
# relative to their source-of-truth inputs.
#
# Strategy: regenerate all derived artifacts in-place, then compare content
# against the committed version. For files with dynamic metadata headers
# (SHA/timestamp), the header lines are stripped before comparison.
#
# Exit 0 = all derived artifacts are fresh
# Exit 1 = stale artifacts detected (with diagnostic output)

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED_FILES=(
  AGENTS.md
  dist/universal-baseline.md
  dist/dx-global-constraints.md
)

# These files embed SHA/timestamp in a 5-line metadata header that changes
# every run. Strip those lines before comparing.
HEADER_SKIP_FILES=(AGENTS.md dist/universal-baseline.md)

echo "Checking derived artifact freshness..."

if ! command -v make >/dev/null 2>&1; then
  echo "FAIL: make required" >&2
  exit 1
fi

make publish-baseline >/dev/null 2>&1

STALE=0
for f in "${DERIVED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "MISSING: $f (expected derived artifact)" >&2
    STALE=1
    continue
  fi

  if ! git show "HEAD:$f" >/dev/null 2>&1; then
    echo "NEW: $f (no committed version - must be committed)" >&2
    STALE=1
    continue
  fi

  NEED_HEADER_SKIP=0
  for hsf in "${HEADER_SKIP_FILES[@]}"; do
    if [ "$f" = "$hsf" ]; then
      NEED_HEADER_SKIP=1
      break
    fi
  done

  if [ "$NEED_HEADER_SKIP" -eq 1 ]; then
    if ! diff <(git show "HEAD:$f" | tail -n +6) <(tail -n +6 "$f") >/dev/null 2>&1; then
      echo "STALE: $f content differs from committed version" >&2
      STALE=1
    fi
  else
    if ! git diff --exit-code -- "$f" >/dev/null 2>&1; then
      echo "STALE: $f differs from committed version" >&2
      STALE=1
    fi
  fi
done

if [ "$STALE" -eq 1 ]; then
  echo "" >&2
  echo "Derived artifacts are stale. Run 'make publish-baseline' and commit the results." >&2
  exit 1
fi

echo "OK: all derived artifacts are fresh"
