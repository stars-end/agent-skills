#!/bin/bash
# check-inbox.sh
# Checks Slack channel for recent messages.
# Usage: ./check-inbox.sh [limit]

DIR="$(dirname "$0")"
if [ -f "$DIR/.config.env" ]; then
    source "$DIR/.config.env"
else
    # Fallback to example if no config (for testing)
    # But usually we expect env vars to be set in shell
    :
fi

CHANNEL=${SLACK_CHANNEL:-"C09MQGMFKDE"}
LIMIT=${1:-5}

if [ -z "$SLACK_MCP_XOXP_TOKEN" ]; then
    echo "❌ SLACK_MCP_XOXP_TOKEN not set"
    exit 1
fi

echo "🔍 Checking last $LIMIT messages in $CHANNEL..."

curl -s -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
    "https://slack.com/api/conversations.history?channel=$CHANNEL&limit=$LIMIT" \
    | jq -r '.messages[] | "[\(.ts | todate)] @\(.user // "unknown"): \(.text)"'

# TODO: Add logic to filter for specifically assigned tasks if needed.
