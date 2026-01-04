#!/bin/bash -i
# session_poc.sh - POC for Session Persistence + Beads Data
# Tests: 1) Session Resume, 2) Interactive Chat, 3) Rich Task Data
# Usage: ./session_poc.sh

set -e
# Force interactive mode loads ~/.bashrc or ~/.zshrc aliases

# --- CONFIG ---
SESSION_UUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
SLEEP_SECONDS=120  # 2 minutes
REPO_PATH=~/affordabot

echo "🧪 SESSION PERSISTENCE POC"
echo "=========================="
echo "Session UUID: $SESSION_UUID"
echo "Sleep Duration: ${SLEEP_SECONDS}s"
echo ""

# --- PHASE 1: Fetch Rich Beads Data ---
echo "📋 Fetching Beads Task Details..."
cd "$REPO_PATH"

# Get first open task with full details
TASK_LINE=$(bd list --status open --limit 1 2>/dev/null | grep -v "Warning" | grep -v "INFO" | grep -E '^[a-z]+-[0-9a-zA-Z]+' | head -n 1)
TASK_ID=$(echo "$TASK_LINE" | awk '{print $1}')

if [ -z "$TASK_ID" ]; then
    echo "❌ No open tasks found. Creating mock task..."
    TASK_ID="mock-poc-task"
    TASK_SUMMARY="This is a mock task for POC testing."
    TASK_DESIGN=""
else
    echo "✅ Found task: $TASK_ID"
    # Fetch full task details using bd show
    TASK_JSON=$(bd show "$TASK_ID" --json 2>/dev/null || echo '[]')
    TASK_SUMMARY=$(echo "$TASK_JSON" | jq -r '.[0].title // "No title"')
    TASK_DESIGN=$(echo "$TASK_JSON" | jq -r '.[0].design // "No design spec"')
fi

echo ""
echo "--- Task Details ---"
echo "ID:      $TASK_ID"
echo "Title:   $TASK_SUMMARY"
echo "Design:  ${TASK_DESIGN:0:100}..."  # Truncate for display
echo "--------------------"
echo ""

# --- PHASE 2: Start Session with Context ---
echo "🚀 Starting Claude session with task context..."

PROMPT="Hello! I am testing session persistence. 
My session UUID is: $SESSION_UUID.
The task I'm working on is: $TASK_ID - $TASK_SUMMARY.

Please acknowledge this message and remember the UUID.
Then wait for my next instruction (I will resume this session after a pause)."

# Use --print to get a one-shot response, with --session-id to establish the session
echo "$PROMPT" | cc-glm --session-id "$SESSION_UUID" -p --output-format text > /tmp/poc_response_1.txt 2>&1

echo "Response 1:"
cat /tmp/poc_response_1.txt | head -n 10
echo ""

# --- PHASE 3: Sleep ---
echo "😴 Sleeping for ${SLEEP_SECONDS}s..."
echo "   (Session is now dormant. Process exited.)"
sleep $SLEEP_SECONDS

# --- PHASE 4: Resume Session ---
echo ""
echo "⏰ Waking up! Resuming session..."

RESUME_PROMPT="I'm back! What was the UUID I gave you earlier? And what task were we discussing?"

echo "$RESUME_PROMPT" | cc-glm --resume "$SESSION_UUID" -p --output-format text > /tmp/poc_response_2.txt 2>&1

echo "Response 2 (Resumed):"
cat /tmp/poc_response_2.txt | head -n 10
echo ""

# --- PHASE 5: Verify ---
echo "--- VERIFICATION ---"
if grep -q "$SESSION_UUID" /tmp/poc_response_2.txt; then
    echo "✅ SUCCESS: Session UUID was remembered!"
else
    echo "⚠️  PARTIAL: UUID not found in response. Checking for task memory..."
    if grep -qi "$TASK_ID" /tmp/poc_response_2.txt; then
        echo "✅ SUCCESS: Task ID was remembered!"
    else
        echo "❌ FAIL: Neither UUID nor Task ID found in resumed response."
    fi
fi

echo ""
echo "📁 Full responses saved to:"
echo "   /tmp/poc_response_1.txt"
echo "   /tmp/poc_response_2.txt"
echo ""
echo "🏁 POC Complete."
