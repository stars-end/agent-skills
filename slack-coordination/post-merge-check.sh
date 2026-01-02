#!/bin/bash
# post-merge-check.sh
# Called after task completion/merge to check for next tasks.
# Implements the "Semi-Auto" coordination loop.
# Usage: ./post-merge-check.sh <completed_task_id> <pr_number>
# Returns: 
#   0 + prints NEXT_TASK_ID (if approved)
#   1 (if no tasks, timeout, or denied)

DIR="$(dirname "$0")"
if [ -f "$DIR/.config.env" ]; then source "$DIR/.config.env"; fi

COMPLETED_TASK=$1
PR_NUM=$2
CHANNEL=${SLACK_CHANNEL:-"C09MQGMFKDE"}
TIMEOUT=${SLACK_APPROVAL_TIMEOUT:-300}
HUMAN_ID=${HUMAN_SLACK_ID:-"U01234567"} # Default placeholder
POLL_INTERVAL=10

if [ -z "$SLACK_MCP_XOXP_TOKEN" ]; then
    echo "❌ SLACK_MCP_XOXP_TOKEN not set" >&2
    exit 1
fi

# 1. Announce Completion
echo "✅ Announcing completion of $COMPLETED_TASK..." >&2

# Dynamic Identity
AGENT_NAME="Agent ($(hostname))"
ICON_EMOJI=":robot_face:" # Can customize per host if needed

curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
    -d "channel=$CHANNEL" \
    -d "username=$AGENT_NAME" \
    -d "icon_emoji=$ICON_EMOJI" \
    -d "text=✅ *Task Completed: $COMPLETED_TASK* (PR #$PR_NUM)\nChecking queue for next task..." \
    "https://slack.com/api/chat.postMessage" > /dev/null

# 2. Check Beads for Next Task
# Assumes 'bd' CLI is available and configured
NEXT_TASK_ID=$(bd list --status ready --limit 1 --format json 2>/dev/null | jq -r '.[0].id // empty')

if [ -z "$NEXT_TASK_ID" ]; then
    echo "ℹ️  No 'ready' tasks found in queue." >&2
    # Verify we can find ANY tasks to differentiate "queue empty" from "bd failed"
    # Actually if bd failed, NEXT_TASK_ID is empty.
    # We should log if bd failed.
    if ! command -v bd &> /dev/null; then
         echo "❌ 'bd' command not found." >&2
         exit 1
    fi
    curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
        -d "channel=$CHANNEL" \
        -d "username=$AGENT_NAME" \
        -d "icon_emoji=$ICON_EMOJI" \
        -d "text=🏁 Queue empty. Session ending." \
        "https://slack.com/api/chat.postMessage" > /dev/null
    exit 1
fi

# 3. Ask for Approval
ECHO_MSG="📋 *Next Task Ready: $NEXT_TASK_ID*\n<@$HUMAN_ID> Should I continue? Reply 'yes' within $((TIMEOUT/60)) min."
echo "❓ Asking for approval for $NEXT_TASK_ID..." >&2

POST_RES=$(curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
    -d "channel=$CHANNEL" \
    -d "username=$AGENT_NAME" \
    -d "icon_emoji=$ICON_EMOJI" \
    -d "text=$ECHO_MSG" \
    "https://slack.com/api/chat.postMessage")

THREAD_TS=$(echo "$POST_RES" | jq -r '.ts')
if [ "$THREAD_TS" == "null" ]; then
    echo "❌ Failed to post message to Slack" >&2
    exit 1
fi

# 4. Poll for Reply
START_TIME=$(date +%s)
echo "⏳ Waiting for human reply..." >&2

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo "⏱️  Timeout reached ($TIMEOUT s)." >&2
        curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
            -d "channel=$CHANNEL" \
            -d "username=$AGENT_NAME" \
            -d "icon_emoji=$ICON_EMOJI" \
            -d "text=⏱️ No response. Ending session gracefully." \
            -d "thread_ts=$THREAD_TS" \
            "https://slack.com/api/chat.postMessage" > /dev/null
        exit 1
    fi

    # Check replies in thread
    REPLIES=$(curl -s -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
        "https://slack.com/api/conversations.replies?channel=$CHANNEL&ts=$THREAD_TS&limit=5")
    
    # Check if HUMAN replied "yes" (case insensitive)
    # We look for a message from HUMAN_ID that contains "yes"
    IS_APPROVED=$(echo "$REPLIES" | jq -r --arg user "$HUMAN_ID" \
        '.messages[] | select(.user == $user) | select(.text | ascii_downcase | contains("yes")) | .ts')

    if [ -n "$IS_APPROVED" ]; then
        echo "✅ Approval received!" >&2
        curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
            -d "channel=$CHANNEL" \
            -d "username=$AGENT_NAME" \
            -d "icon_emoji=$ICON_EMOJI" \
            -d "text=🚀 Starting $NEXT_TASK_ID..." \
            -d "thread_ts=$THREAD_TS" \
            "https://slack.com/api/chat.postMessage" > /dev/null
            
        # RETURN THE TASK ID to caller
        echo "$NEXT_TASK_ID"
        exit 0
    fi
    
    # Check for "no" or "stop"
    IS_DENIED=$(echo "$REPLIES" | jq -r --arg user "$HUMAN_ID" \
        '.messages[] | select(.user == $user) | select(.text | ascii_downcase | contains("no") or contains("stop")) | .ts')
        
    if [ -n "$IS_DENIED" ]; then
         echo "🛑 Request denied." >&2
         curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
            -d "channel=$CHANNEL" \
            -d "username=$AGENT_NAME" \
            -d "icon_emoji=$ICON_EMOJI" \
            -d "text=🛑 Understood. Stopping session." \
            -d "thread_ts=$THREAD_TS" \
            "https://slack.com/api/chat.postMessage" > /dev/null
         exit 1
    fi

    sleep $POLL_INTERVAL
done
