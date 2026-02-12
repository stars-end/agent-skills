#!/usr/bin/env bash
# heartbeat-parser.sh - Parse HEARTBEAT.md deterministically (no LLM)
# Usage: heartbeat-parser.sh [check|status]

set -euo pipefail

HEARTBEAT_FILE="$HOME/.dx-state/HEARTBEAT.md"

# Parse status from heartbeat (deterministic grep/awk only)
parse_status() {
    if [[ ! -f "$HEARTBEAT_FILE" ]]; then
        echo "UNKNOWN:heartbeat_missing"
        return 1
    fi

    # Look for Status: lines - get all statuses
    local statuses
    statuses=$(grep "^Status:" "$HEARTBEAT_FILE" 2>/dev/null | awk '{print $2}' || echo "")

    if [[ -z "$statuses" ]]; then
        echo "UNKNOWN:parse_failed"
        return 1
    fi

    # Check for any ERROR or WARNING
    if echo "$statuses" | grep -q "^ERROR"; then
        echo "ERROR:found"
        return 1
    fi

    if echo "$statuses" | grep -q "^WARNING"; then
        echo "WARNING:found"
        return 1
    fi

    # All OK
    if echo "$statuses" | grep -q "^OK"; then
        echo "OK"
        return 0
    fi

    echo "UNKNOWN:unexpected_status"
    return 1
}

# Check if any repo has WARNING or ERROR status
check_health() {
    local status
    status=$(parse_status)
    local rc=$?

    case "$status" in
        OK)
            echo "HEALTHY"
            return 0
            ;;
        WARNING*)
            echo "DEGRADED:$status"
            return 1
            ;;
        ERROR*)
            echo "UNHEALTHY:$status"
            return 1
            ;;
        *)
            echo "UNKNOWN:$status"
            return 1
            ;;
    esac
}

# Get detailed status for all sections
get_detailed_status() {
    if [[ ! -f "$HEARTBEAT_FILE" ]]; then
        echo "ERROR: heartbeat file not found at $HEARTBEAT_FILE"
        return 1
    fi

    echo "=== HEARTBEAT Status ==="
    echo "File: $HEARTBEAT_FILE"
    echo ""

    # Extract all status lines with their section context using grep/sed
    local current_section=""
    while IFS= read -r line; do
        # Check for section header (### Section Name)
        if echo "$line" | grep -q "^### "; then
            current_section=$(echo "$line" | sed 's/^### //')
        # Check for Status: line
        elif echo "$line" | grep -q "^Status: "; then
            local status
            status=$(echo "$line" | sed 's/^Status: //')
            echo "[$current_section] Status: $status"
        # Check for Last run: line
        elif echo "$line" | grep -q "^Last run: "; then
            local last_run
            last_run=$(echo "$line" | sed 's/^Last run: //')
            echo "[$current_section] Last run: $last_run"
        fi
    done < "$HEARTBEAT_FILE"
}

# Main
ACTION="${1:-status}"

case "$ACTION" in
    status)
        parse_status
        ;;
    check)
        check_health
        ;;
    detail|details)
        get_detailed_status
        ;;
    *)
        echo "Usage: $0 [check|status|detail]"
        exit 1
        ;;
esac
