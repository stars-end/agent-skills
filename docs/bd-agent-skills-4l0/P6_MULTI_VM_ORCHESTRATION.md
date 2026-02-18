# P6: Multi-VM Orchestration Architecture

**Added:** 2026-01-04
**Updated:** 2026-02-18
**Status:** IMPLEMENTED with hardened SSH fanout

---

## Overview

This document extends the existing multi-agent coordination system with a refined multi-VM orchestration architecture that supports:

1. **Multi-orchestrator support** (Antigravity, Claude Code, etc.)
2. **Multi-OpenCode server routing** (homedesktop-wsl, macmini, epyc6)
3. **Dual-write pattern** (HTTP for speed, Slack for visibility)
4. **Human interrupt capability** via Slack audit channel

---

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                           Multi-VM Fleet                                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                         Orchestrator Layer                            │ │
│  │                                                                       │ │
│  │     You ───▶ Antigravity (homedesktop-wsl)                           │ │
│  │               OR Claude Code (macmini)                                │ │
│  │                                                                       │ │
│  │     Rule: Talk to ONE orchestrator at a time                         │ │
│  │     Orchestrators can be swapped; Beads maintains state              │ │
│  │                                                                       │ │
│  └─────────────────────────────┬────────────────────────────────────────┘ │
│                                │                                          │
│                    ┌───────────┴───────────┐                              │
│                    ▼                       ▼                              │
│              HTTP dispatch           Slack audit                          │
│              (fast path)             #agent-coordination                  │
│                                      (visibility)                         │
│                    │                                                      │
│  ┌─────────────────┴──────────────────────────────────────────────────┐  │
│  │                         OpenCode Servers                            │  │
│  │                                                                     │  │
│  │   homedesktop-wsl:4105      macmini:4105          epyc6:4105       │  │
│  │   ┌─────────────────┐      ┌─────────────────┐   ┌────────────────┐│  │
│  │   │ OpenCode Server │      │ OpenCode Server │   │ OpenCode Server││  │
│  │   │ (local)         │      │ (Tailscale)     │   │ (Tailscale)    ││  │
│  │   └────────┬────────┘      └────────┬────────┘   └───────┬────────┘│  │
│  │            │                        │                     │         │  │
│  │            └────────────────────────┴─────────────────────┘         │  │
│  │                                 │                                   │  │
│  │                                 ▼                                   │  │
│  │                    ┌─────────────────────────┐                      │  │
│  │                    │   Shared Git Remote     │                      │  │
│  │                    │   (github/affordabot)   │                      │  │
│  │                    └─────────────────────────┘                      │  │
│  │                                 │                                   │  │
│  │                                 ▼                                   │  │
│  │                    ┌─────────────────────────┐                      │  │
│  │                    │        Beads            │                      │  │
│  │                    │   (distributed lock)    │                      │  │
│  │                    └─────────────────────────┘                      │  │
│  │                                                                     │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Two Communication Routes

### Route 1: Agent-to-Agent (HTTP API)
- **Transport:** Direct HTTP to OpenCode server
- **Speed:** Fast (no Slack latency)
- **Visibility:** Invisible to human (unless we add audit)
- **Use case:** Orchestrator dispatching to workers

### Route 2: Agent-to-Human (Slack)
- **Transport:** Slack messages via Socket Mode + MCP
- **Speed:** Slower (Slack latency)
- **Visibility:** Full human visibility
- **Use case:** Human initiating tasks, interrupts

### Combined: Dual-Write Pattern (Recommended)
```
Orchestrator:
  1. POST to Slack: "Dispatching bd-xyz to epyc6..."  (visibility)
  2. POST to OpenCode HTTP API                        (speed)
  3. POST to Slack: "Session created: ses_abc"        (visibility)
  4. Wait for completion
  5. POST to Slack: "Completed: tests passed"         (visibility)
```

---

## VM Configuration

### Endpoints Config: `~/.agent-skills/vm-endpoints.json`
```json
{
  "vms": {
    "homedesktop": {
      "opencode": "http://localhost:4105",
      "ssh": null,
      "tailscale": null,
      "local": true
    },
    "macmini": {
      "opencode": "http://macmini.tail76761.ts.net:4105",
      "ssh": "fengning@macmini",
      "tailscale": "macmini.tail76761.ts.net"
    },
    "epyc6": {
      "opencode": "http://epyc6.tail76761.ts.net:4105",
      "ssh": "feng@epyc6",
      "tailscale": "epyc6.tail76761.ts.net"
    }
  },
  "default_vm": "epyc6",
  "slack_audit_channel": "C09MQGMFKDE"
}
```

---

## dx-dispatch Script

### Usage
```bash
# Basic dispatch
dx-dispatch epyc6 affordabot "Run make test"

# With session resume
dx-dispatch epyc6 affordabot "Continue work" --session ses_abc123

# With Slack audit
dx-dispatch macmini prime-radiant "Fix linting" --slack

# Parallel dispatch to all VMs
dx-dispatch --all affordabot "Run make test"
```

### Implementation
```bash
#!/bin/bash
# dx-dispatch - Dispatch task to remote OpenCode agent

VM=$1
REPO=$2
TASK=$3
SLACK_AUDIT=${SLACK_AUDIT:-true}

# Load config
CONFIG=~/.agent-skills/vm-endpoints.json
OPENCODE_URL=$(jq -r ".vms.$VM.opencode" $CONFIG)
AUDIT_CHANNEL=$(jq -r ".slack_audit_channel" $CONFIG)

# Optional: Post to Slack for visibility
if [ "$SLACK_AUDIT" = "true" ]; then
    post_to_slack "$AUDIT_CHANNEL" "[$(hostname)] Dispatching to $VM: $TASK"
fi

# Create session
SESSION=$(curl -s -X POST "$OPENCODE_URL/session" -d '{"title":"'"$REPO"'"}' | jq -r '.id')

# Send task
curl -s -X POST "$OPENCODE_URL/session/$SESSION/message" \
    -H "Content-Type: application/json" \
    -d '{"parts":[{"type":"text","text":"'"$TASK"'"}]}'

# Audit completion
if [ "$SLACK_AUDIT" = "true" ]; then
    post_to_slack "$AUDIT_CHANNEL" "[$VM] Session $SESSION completed"
fi
```

---

## Beads Integration

### Conflict Avoidance
```python
def assign_work(issue_id, target_vm):
    issue = bd_show(issue_id)
    if issue.assignee and issue.assignee != target_vm:
        raise AlreadyAssignedError(f"{issue_id} assigned to {issue.assignee}")
    bd_update(issue_id, assignee=target_vm)
```

### Session Tracking
```
bd-xyz:
  assignee: epyc6           # Which VM is working on it
  session: ses_abc123       # OpenCode session ID
  worktree: /path/to/wt     # Git worktree path
  status: in-progress       # Beads status
```

---

## Human Interrupt Flow

```
You: "Stop the epyc6 task, they're on wrong branch"
     │
     ▼
Orchestrator:
  1. POST to Slack: "Aborting epyc6 session ses_abc"
  2. Send cancel signal to OpenCode (if supported)
  3. Update Beads: status=blocked
  4. POST to Slack: "Stopped. What next?"
     │
     ▼
You: "Switch to feature-xyz branch and retry"
```

---

## SSH Fanout Hardening (bd-xga8.1.2)

The SSH fanout path is hardened with deterministic preflight checks, bounded retries,
and standardized logging.

### Canonical Host->User Mapping

Source of truth in `lib/fleet/ssh_fanout.py`:

| Hostname | User | Auth Mode | Aliases |
|----------|------|-----------|---------|
| homedesktop-wsl | fengning | local | homedesktop, wsl, local |
| macmini | fengning | tailscale | mac, mac-mini |
| epyc6 | feng | tailscale | epyc, gpu |

### Preflight Checks

All SSH fanout operations run these checks before connection:

1. **Host mapping validation** - Verifies host has canonical user mapping
2. **DNS resolution** - Hostname must be resolvable (5s timeout)
3. **TCP reachability** - SSH port 22 must be accessible (5s timeout)
4. **Auth mode validation** - Required auth method must be available

Preflight failures return `PREFLIGHT_FAILED` terminal state with detailed error.

### Bounded Retry Semantics

- Maximum **2 attempts** (1 initial + 1 retry)
- **2-second delay** between retries
- **No retry** on authentication failures (terminal state)
- Clear terminal states:
  - `SUCCESS` - Command completed with exit code 0
  - `FAILURE` - Command failed after all retries
  - `TIMEOUT` - Command timed out
  - `ABORTED` - Operation was aborted
  - `PREFLIGHT_FAILED` - Preflight checks failed

### Standardized Logging

All fanout operations log with consistent key=value structure:

```
preflight_ok host=epyc6 user=feng auth_mode=tailscale duration_ms=150
success host=epyc6 user=feng command="make test" attempt=1 duration_ms=2340
failure host=epyc6 user=feng command="make test" final_error="Exit code 1" attempts=2
```

### Programmatic API

```python
from lib.fleet import (
    fanout_ssh,
    run_preflight_checks,
    PreflightStatus,
    FanoutOutcome,
)

# Run preflight checks
preflight = run_preflight_checks("epyc6")
if preflight.status != PreflightStatus.OK:
    print(f"Preflight failed: {preflight.error_detail}")
    return

# Execute command with hardened fanout
result = fanout_ssh(
    host="epyc6",
    command="make test",
    timeout_sec=120.0,
    max_retries=1,  # Total 2 attempts
    preflight=True,
)

if result.outcome == FanoutOutcome.SUCCESS:
    print(result.stdout)
else:
    print(f"Failed: {result.error} (attempts: {result.attempts})")
```

---

## Summary Table

| Component | Qty | Purpose |
|-----------|-----|---------|
| Orchestrator | 1 active | Human interface, dispatch routing |
| OpenCode Server | 3 | Execute AI tasks on VMs |
| Slack Channel | 1 | Audit trail, human interrupt |
| Beads | 1 shared | Distributed lock, state tracking |
| dx-dispatch | 1 | CLI for dispatching tasks |

---

## Implementation Phases

| Phase | Description | Status |
|-------|-------------|--------|
| P0-P5 | Original implementation | ✅ COMPLETE |
| **P6.1** | Create vm-endpoints.json config | ✅ COMPLETE |
| **P6.2** | Implement dx-dispatch script | ✅ COMPLETE |
| **P6.3** | Add Slack audit to dispatches | ✅ COMPLETE |
| **P6.4** | Test multi-VM routing | ✅ COMPLETE |
| **P6.5** | Integration tests for full flow | ✅ COMPLETE |
| **P6.6** | SSH fanout hardening (bd-xga8.1.2) | ✅ COMPLETE |
  - Preflight checks (host resolvable, user mapping, auth guard)
  - Bounded retry semantics (max 2 attempts)
  - Standardized logging (host, user, command, outcome)
  - Canonical host->user mapping |
