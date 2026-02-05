#!/usr/bin/env bash
#
# dx-session-lock.sh
#
# Manages .dx-session-lock for repos and worktrees.
# Freshness threshold is 4 hours (14400s).
#
# Usage:
#   dx-session-lock.sh touch <path>
#   dx-session-lock.sh is-fresh <path>
#   dx-session-lock.sh clear <path>
#
set -euo pipefail

CMD="${1:-}"
TARGET_PATH="${2:-.}"
LOCK_FILE="$TARGET_PATH/.dx-session-lock"
FRESH_THRESHOLD=14400 # 4h

case "$CMD" in
    touch)
        # Target path should exist
        if [[ ! -d "$TARGET_PATH" ]]; then
            echo "Error: target directory $TARGET_PATH does not exist"
            exit 1
        fi
        echo "$(date +%s)::" > "$LOCK_FILE"
        ;;
    is-fresh)
        if [[ ! -f "$LOCK_FILE" ]]; then
            # Also check for .git/index.lock as a fallback active indicator
            if [[ -f "$TARGET_PATH/.git/index.lock" ]]; then
                exit 0
            fi
            exit 1
        fi
        
        LOCK_TS=$(cut -d':' -f1 "$LOCK_FILE" 2>/dev/null || echo "0")
        NOW=$(date +%s)
        AGE=$((NOW - LOCK_TS))
        
        if [[ $AGE -lt $FRESH_THRESHOLD ]]; then
            exit 0
        else
            exit 1
        fi
        ;;
    clear)
        if [[ -f "$LOCK_FILE" ]]; then
            rm "$LOCK_FILE"
        fi
        ;;
    *)
        echo "Usage: dx-session-lock.sh {touch|is-fresh|clear} <path>"
        exit 1
        ;;
esac
