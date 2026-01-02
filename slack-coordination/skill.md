---
description: Check Slack for new task assignments and coordinate with other agents
triggers:
  - "check slack"
  - "poll inbox"
  - "slack coordination"
  - "finish task"
---

# Slack Coordination Skill

This skill allows the agent to coordinate with other agents and humans via Slack.

## Usage

### 1. Start of Session (Manual Polling)
```bash
~/agent-skills/slack-coordination/check-inbox.sh
```
Check for new messages or tasks assigned to you.

### 2. End of Task (Completion Loop)
```bash
~/agent-skills/slack-coordination/post-merge-check.sh <TASK_ID> <PR_NUMBER>
```
Call this after merging a PR. It will:
1. Announce completion.
2. Check for the next blocked task.
3. Ask the human for approval.
4. If approved, output the `NEXT_TASK_ID`.

### 3. Resource Locking
The system enforces ONE agent per machine.
```bash
~/agent-skills/slack-coordination/can-dispatch.sh
```
Run this before starting any heavy sub-tasks or new sessions.

## Configuration
Ensure `~/.agent-skills/slack-coordination/.config.env` is set up or env vars are exported:
- `SLACK_MCP_XOXP_TOKEN`
- `SLACK_CHANNEL`
- `HUMAN_SLACK_ID`
