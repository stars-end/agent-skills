# Autonomous Slack Dispatch Workflow

**For: GitHub CI Integration Evaluation**

---

## What It Does

Dispatches tasks to remote VMs running OpenCode agents, with Slack notifications for status updates. Agents post completion summaries to Slack autonomously.

---

## Architecture

```
┌─────────────────┐     HTTP API      ┌──────────────────┐
│  GitHub Action  │ ───────────────── │   OpenCode VM    │
│  or Dispatcher  │    POST /session  │   (epyc6, etc)   │
└─────────────────┘                   └────────┬─────────┘
                                               │
                                          Slack MCP
                                               │
                                               ▼
                                      ┌──────────────┐
                                      │    Slack     │
                                      │   #channel   │
                                      └──────────────┘
```

---

## Quick Start

### 1. Dispatch a Task
```bash
curl -X POST http://<vm>:4105/session \
  -H "Content-Type: application/json" \
  -d '{"title": "ci-task"}'
# Returns: {"id": "ses_xxx"}

curl -X POST http://<vm>:4105/session/ses_xxx/message \
  -H "Content-Type: application/json" \
  -d '{
    "parts": [{
      "type": "text",
      "text": "Run make test. After completing, use slack_conversations_add_message to post summary to channel C09MQGMFKDE."
    }]
  }'
```

### 2. Or Use dx-dispatch (Wrapper Script)
```bash
dx-dispatch epyc6 "Run make test" --slack
```

---

## Agent Notification Pattern

Include this in your task prompt to enable autonomous Slack notifications:

```
After completing the task, use slack_conversations_add_message to post 
a completion summary to channel <CHANNEL_ID>.

Include: 
- Task status (✅ success / ❌ failure)
- Brief summary of what was done
- Any errors encountered
```

---

## GitHub Actions Example

```yaml
name: Dispatch to Agent
on: workflow_dispatch

jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - name: Create session
        id: session
        run: |
          RESP=$(curl -s -X POST http://${{ secrets.VM_HOST }}:4105/session \
            -H "Content-Type: application/json" \
            -d '{"title": "gh-action-${{ github.run_id }}"}')
          echo "session_id=$(echo $RESP | jq -r .id)" >> $GITHUB_OUTPUT
      
      - name: Dispatch task
        run: |
          curl -X POST http://${{ secrets.VM_HOST }}:4105/session/${{ steps.session.outputs.session_id }}/message \
            -H "Content-Type: application/json" \
            -d '{
              "parts": [{
                "type": "text", 
                "text": "Run CI task. Post result to Slack channel ${{ secrets.SLACK_CHANNEL }}."
              }]
            }'
```

---

## Prerequisites

| Requirement | Description |
|-------------|-------------|
| OpenCode server | Running on VM with `opencode serve --port 4105` |
| Slack MCP | Configured in opencode.json with `SLACK_MCP_XOXB_TOKEN` |
| Network access | CI can reach VM:4105 (or use SSH tunnel) |

---

## Slack MCP Configuration (on VM)

```json
// ~/.config/opencode/opencode.json
{
  "mcp": {
    "slack": {
      "type": "local",
      "command": ["npx", "-y", "slack-mcp-server@latest", "--transport", "stdio"],
      "enabled": true,
      "environment": {
        "SLACK_MCP_XOXB_TOKEN": "{env:SLACK_MCP_XOXB_TOKEN}",
        "SLACK_MCP_ADD_MESSAGE_TOOL": "true"
      }
    }
  }
}
```

---

## Slack MCP Tools Available to Agent

| Tool | Use |
|------|-----|
| `slack_conversations_add_message` | Post to channel |
| `slack_conversations_history` | Read messages |
| `slack_channels_list` | List channels |

---

## Key Design Decisions

1. **Agent-as-notifier**: Agent posts to Slack, not the dispatcher
2. **Stateless dispatch**: No polling required - agent handles completion
3. **MCP-based**: Uses standard MCP protocol for Slack access
4. **Prompt-driven**: Notification behavior controlled by task prompt
