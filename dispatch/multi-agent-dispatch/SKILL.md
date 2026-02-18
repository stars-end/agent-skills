---
name: multi-agent-dispatch
description: Cross-VM task dispatch using dx-dispatch (canonical). Supports SSH dispatch to canonical VMs (homedesktop-wsl, macmini, epyc12), Jules Cloud dispatch for async work, and fleet orchestration. EPYC6 is currently disabled - see enablement gate.
---

# Multi-Agent Dispatch

`dx-dispatch` is the canonical tool for cross-VM and cloud dispatch.

## When to Use

- Task needs **specific VM** (GPU → epyc12, macOS → macmini)
- **Parallelize** work across VMs
- **Jules Cloud** dispatch for async work
- Need **status notifications** via Slack

## Usage

### SSH Dispatch (default)

```bash
# Dispatch to canonical VMs (use epyc12, NOT epyc6)
dx-dispatch epyc12 "Run make test in ~/affordabot"
dx-dispatch macmini "Build the iOS app"
dx-dispatch homedesktop-wsl "Run integration tests"

# Check VM status
dx-dispatch --list

# Resume existing session
dx-dispatch epyc12 "Continue" --session ses_abc123

# Wait for completion
dx-dispatch epyc12 "Run tests" --wait --timeout 600
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
dx-dispatch --status epyc12
```

## Canonical VMs

| VM | User | Auth Mode | Capabilities | Status |
|----|------|-----------|--------------|--------|
| homedesktop-wsl | fengning | local | Primary dev, DCG, CASS | Enabled |
| macmini | fengning | tailscale | macOS builds, iOS | Enabled |
| epyc12 | fengning | tailscale | Linux compute | **Default Linux** |
| epyc6 | feng | tailscale | GPU work, ML training | **DISABLED** |

**EPYC6 Enablement Gate:** EPYC6 is currently disabled pending resolution of runtime/session issues. Use `epyc12` as the default Linux dispatch target. See `extended/cc-glm/docs/EPYC6_ENABLEMENT_GATE.md` for preflight checks and enablement criteria.

## SSH Fanout Hardening

Dispatch operations use hardened SSH fanout with:

### Preflight Checks
All SSH operations run deterministic preflight checks before attempting connection:
1. **Host mapping validation** - Ensures host has canonical user mapping
2. **DNS resolution** - Verifies hostname is resolvable
3. **TCP reachability** - Checks SSH port is accessible
4. **Auth mode validation** - Confirms required auth method is available

### Bounded Retry Semantics
- Maximum 2 attempts (1 retry) per operation
- 2-second delay between retries
- No retry on authentication failures (terminal)
- Clear terminal states: SUCCESS, FAILURE, TIMEOUT, ABORTED, PREFLIGHT_FAILED

### Standardized Logging
All fanout operations log with consistent structure:
```
preflight_ok host=epyc6 user=feng auth_mode=tailscale duration_ms=150
success host=epyc6 user=feng command="make test" attempt=1 duration_ms=2340
```

### Programmatic Usage
```python
from lib.fleet import fanout_ssh, run_preflight_checks, PreflightStatus

# Run preflight checks
preflight = run_preflight_checks("epyc6")
if preflight.status == PreflightStatus.OK:
    result = fanout_ssh("epyc6", "make test", timeout_sec=120.0)
    if result.outcome == FanoutOutcome.SUCCESS:
        print(result.stdout)
    else:
        print(f"Failed: {result.error}")
```

## Slack Notifications

Use `--slack` to enable audit trail (default: enabled):

```bash
dx-dispatch epyc12 "Run tests" --slack
```

Include in task prompt for completion notifications:
```
After completing, use slack_conversations_add_message
to post summary to channel C09MQGMFKDE.
```

## Full Guide

See [docs/MULTI_AGENT_COMMS.md](../../docs/MULTI_AGENT_COMMS.md)
