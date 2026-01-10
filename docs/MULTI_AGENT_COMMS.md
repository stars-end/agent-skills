# Multi-Agent Communication Guide

## When to Use Multi-Agent Dispatch

| Scenario | Use Multi-Agent? | Example |
|----------|------------------|---------|
| Task needs specific VM | ✅ Yes | GPU work → epyc6, macOS build → macmini |
| Parallelize work | ✅ Yes | Run tests on multiple VMs simultaneously |
| Need status updates | ✅ Yes | Long tasks with Slack notifications |
| Simple local work | ❌ No | Tasks that work on current VM |

---

## Quick Reference

### Dispatch a Task
```bash
dx-dispatch <vm> "<task>"
dx-dispatch epyc6 "Run make test in ~/affordabot"
dx-dispatch macmini "Build iOS app"
```

### Check VMs
```bash
dx-dispatch --list      # List all VMs with status
dx-dispatch --status epyc6  # Check specific VM
```

### Resume Session
```bash
dx-dispatch epyc6 "Continue" --session ses_abc123
```

---

## Adding Slack Notifications to Tasks

### Basic Pattern
Include this in your task prompt:
```
After completing, use slack_conversations_add_message to post 
a summary to channel C09MQGMFKDE.
```

### Progress Updates for Long Tasks
```
Post progress to Slack #social (C09MQGMFKDE):
- When starting: '🔄 Starting on <vm>...'
- When complete: '✅ Complete: <summary>'
- On failure: '❌ Failed: <error>'
```

---

## Available VMs

| VM | Best For | OpenCode URL |
|----|----------|--------------|
| epyc6 | Heavy compute, Linux builds | `http://epyc6.tail76761.ts.net:4105` |
| macmini | macOS builds, iOS | `http://macmini.tail76761.ts.net:4105` |
| homedesktop | Local testing | `http://localhost:4105` |

---

## Slack MCP Tools

Agents on these VMs have native Slack access:

| Tool | Use |
|------|-----|
| `slack_conversations_add_message` | Post to channel |
| `slack_conversations_history` | Read messages |
| `slack_channels_list` | List channels |
| `slack_conversations_replies` | Thread replies |

**Default Channel**: `C09MQGMFKDE` (#social)

---

## Architecture

```
┌─────────────┐    dx-dispatch    ┌─────────────┐
│ Coordinator │ ───────────────── │   epyc6     │
│ (local)     │                   │  OpenCode   │
└─────────────┘                   └──────┬──────┘
       │                                 │
       │                           Slack MCP
       │                                 │
       ▼                                 ▼
┌─────────────┐                   ┌─────────────┐
│   macmini   │                   │   Slack     │
│  OpenCode   │ ──── Slack MCP ── │  #social    │
└─────────────┘                   └─────────────┘
```

---

## Troubleshooting

### VM Not Responding
```bash
# Restart OpenCode
ssh feng@epyc6 'systemctl --user restart opencode.service'
ssh fengning@macmini 'launchctl kickstart -k ~/Library/LaunchAgents/com.agent.opencode-server.plist'
```

### Slack Tools Not Available
Restart OpenCode to reload MCP configuration.

### Session Resume Fails
Create a new session - old sessions may have expired.
