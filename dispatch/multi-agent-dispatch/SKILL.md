---
name: multi-agent-dispatch
activation:
  - "dispatch task"
  - "run on vm"
  - "switch vm"
  - "jules dispatch"
  - "remote task"
  - "cross-vm"
description: Cross-VM task dispatch using dx-dispatch (canonical). Supports SSH dispatch to canonical VMs (homedesktop-wsl, macmini, epyc6), Jules Cloud dispatch for async work, and fleet orchestration.
---

# Multi-Agent Dispatch

`dx-dispatch` is the canonical tool for cross-VM and cloud dispatch.

## When to Use

- Task needs **specific VM** (GPU → epyc6, macOS → macmini)
- **Parallelize** work across VMs
- **Jules Cloud** dispatch for async work
- Need **status notifications** via Slack

## Usage

### SSH Dispatch (default)

```bash
# Dispatch to canonical VMs
dx-dispatch epyc6 "Run make test in ~/affordabot"
dx-dispatch macmini "Build the iOS app"
dx-dispatch homedesktop-wsl "Run integration tests"

# Check VM status
dx-dispatch --list

# Resume existing session
dx-dispatch epyc6 "Continue" --session ses_abc123

# Wait for completion
dx-dispatch epyc6 "Run tests" --wait --timeout 600
```

### Jules Cloud Dispatch

```bash
# Dispatch Beads issue to Jules Cloud
dx-dispatch --jules --issue bd-123

# Dry run (preview prompt)
dx-dispatch --jules --issue bd-123 --dry-run
```

### Fleet Operations

```bash
# Finalize PR for a session
dx-dispatch --finalize-pr ses_abc123 --beads bd-123

# Abort a running session
dx-dispatch --abort ses_abc123

# Check VM health
dx-dispatch --status epyc6
```

### Canonical VMs

| VM | User | Capabilities |
|----|------|--------------|
| homedesktop-wsl | fengning | Primary dev, DCG, CASS |
| macmini | fengning | macOS builds, iOS |
| epyc6 | feng | GPU work, ML training |

## Slack Notifications

Use `--slack` to enable audit trail (default: enabled):

```bash
dx-dispatch epyc6 "Run tests" --slack
```

Include in task prompt for completion notifications:
```
After completing, use slack_conversations_add_message
to post summary to channel C09MQGMFKDE.
```

## Full Guide

See [docs/MULTI_AGENT_COMMS.md](../../docs/MULTI_AGENT_COMMS.md)
