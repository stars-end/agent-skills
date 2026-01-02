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
HUMAN_ID=${HUMAN_SLACK_ID:-"U09LSQ5JEQ5"} # Default placeholder
POLL_INTERVAL=5

if [ -z "$SLACK_MCP_XOXP_TOKEN" ]; then
    echo "❌ SLACK_MCP_XOXP_TOKEN not set" >&2
    exit 1
fi

# 1. Announce Completion
echo "✅ Announcing completion of $COMPLETED_TASK..." >&2

# Dynamic Identity
AGENT_NAME="Agent ($(hostname))"
ICON_EMOJI=":robot_face:" # Can customize per host if needed

FIRST_RES=$(curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
    -d "channel=$CHANNEL" \
    --data-urlencode "username=$AGENT_NAME" \
    --data-urlencode "icon_emoji=$ICON_EMOJI" \
    --data-urlencode "text=✅ *Task Completed: $COMPLETED_TASK* (PR #$PR_NUM)
Checking queue for next task..." \
    "https://slack.com/api/chat.postMessage")
echo "First Post Result: $FIRST_RES" >&2

# 2. Check Beads for Next Task
# Assumes 'bd' CLI is available and configured
# Use 'open' status to capture all candidate tasks.
# Parse text output (ID is first column) because JSON format is unreliable on some hosts
NEXT_TASK_ID=$(bd list --status open --limit 1 2>/dev/null | grep -v "Warning" | grep -v "INFO" | grep -E '^[a-z]+-[0-9a-zA-Z]+' | head -n 1 | awk '{print $1}')

if [ -z "$NEXT_TASK_ID" ]; then
    echo "ℹ️  No open tasks found in queue." >&2
    # Verify we can find ANY tasks to differentiate "queue empty" from "bd failed"
    if ! command -v bd &> /dev/null; then
         echo "❌ 'bd' command not found." >&2
         exit 1
    fi
    curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
        -d "channel=$CHANNEL" \
        --data-urlencode "username=$AGENT_NAME" \
        --data-urlencode "icon_emoji=$ICON_EMOJI" \
        --data-urlencode "text=🏁 Queue empty. Session ending." \
        "https://slack.com/api/chat.postMessage" > /dev/null
    exit 1
fi

# 3. Ask for Approval
ECHO_MSG="📋 *Next Task Ready: $NEXT_TASK_ID* [Host: $(hostname)]
<@$HUMAN_ID> Should I continue? Reply 'yes' within appropriate timeframe."
echo "❓ Asking for approval for $NEXT_TASK_ID..." >&2

POST_RES=$(curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
    -d "channel=$CHANNEL" \
    --data-urlencode "username=$AGENT_NAME" \
    --data-urlencode "icon_emoji=$ICON_EMOJI" \
    --data-urlencode "text=$ECHO_MSG" \
    "https://slack.com/api/chat.postMessage")

echo "Second Post Result: $POST_RES" >&2

THREAD_TS=$(echo "$POST_RES" | jq -r '.ts')
if [ "$THREAD_TS" == "null" ] || [ "$THREAD_TS" == "" ]; then
    echo "❌ Failed to post message to Slack. Response: $POST_RES" >&2
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
            --data-urlencode "username=$AGENT_NAME" \
            --data-urlencode "icon_emoji=$ICON_EMOJI" \
            --data-urlencode "text=⏱️ No response after 60+ mins. Ending session." \
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
            --data-urlencode "username=$AGENT_NAME" \
            --data-urlencode "icon_emoji=$ICON_EMOJI" \
            --data-urlencode "text=🚀 Starting $NEXT_TASK_ID..." \
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
            --data-urlencode "username=$AGENT_NAME" \
            --data-urlencode "icon_emoji=$ICON_EMOJI" \
            --data-urlencode "text=🛑 Understood. Stopping session." \
            -d "thread_ts=$THREAD_TS" \
            "https://slack.com/api/chat.postMessage" > /dev/null
         exit 1
    fi

    # Backoff logic: 1/2/4/8/16/32 minutes
    # If we just waited 32 mins (1920s), the next POLL_INTERVAL would be 64m.
    # We exit gracefully if the NEXT interval exceeds the 32m step.
    
    echo "Sleeping for $POLL_INTERVAL seconds..." >&2
    sleep $POLL_INTERVAL
    
    POLL_INTERVAL=$((POLL_INTERVAL * 2))
    
    # Cap logic / Exit logic
    # If standard doubling pattern exceeds 32 mins (1920s) -> 3840s (64m)
    # We don't want to wait 64 mins. We check this AT START of next loop via TIMEOUT
    # OR we can exit here if we strictly want the sequence and then stop.
    
    # The user said "and then it just ends". 
    # Current loop: Checked, Slept X. Update X to 2X. 
    # If 2X > 1920 (32 mins), then we have Done 32mins -> Next is 64mins.
    # Actually, if we just slept 32 mins, we check one last time. 
    # Then we prepare to sleep 64 mins.
    # We should catch it here.
    
    if [ $POLL_INTERVAL -gt 2000 ]; then
        echo "⏱️  Max backoff reached. Ending session." >&2
        curl -s -X POST -H "Authorization: Bearer $SLACK_MCP_XOXP_TOKEN" \
            -d "channel=$CHANNEL" \
            --data-urlencode "username=$AGENT_NAME" \
            --data-urlencode "icon_emoji=$ICON_EMOJI" \
            --data-urlencode "text=⏱️ No response after sequence (Last wait: 32m). Session ending." \
            -d "thread_ts=$THREAD_TS" \
            "https://slack.com/api/chat.postMessage" > /dev/null
        exit 1
    fi
done
