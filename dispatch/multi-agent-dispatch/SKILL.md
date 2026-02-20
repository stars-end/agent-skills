---
name: multi-agent-dispatch
description: |
  Cross-VM task dispatch with dx-runner as canonical governance runner and OpenCode as primary execution lane.
  dx-dispatch is a BREAK-GLASS compatibility shim for remote fanout when dx-runner is unavailable.
  EPYC6 is currently disabled - see enablement gate.
tags: [workflow, dispatch, dx-runner, governance, cross-vm]
---

# Multi-Agent Dispatch (dx-runner Canonical)

`dx-runner` is the **canonical dispatch/governance surface**. OpenCode (`opencode run` / `opencode serve`) remains the primary execution lane. 

`dx-dispatch` is a **BREAK-GLASS compatibility shim** for remote fanout when dx-runner direct dispatch is unavailable. Use only for legacy cross-VM orchestration.

## Dispatch Lanes

- **Primary**: `dx-runner --provider opencode` (governed, canonical)
- **Reliability backstop**: `dx-runner --provider cc-glm` when governance gates require fallback
- **Break-glass**: `dx-dispatch` (compatibility shim, deprecated)

## When to Use

- Task needs **specific VM** (GPU → epyc12, macOS → macmini)
- **Parallelize** work across VMs
- **Jules Cloud** dispatch for async work
- Need **status notifications** via Slack

## Usage

### Governed Local Dispatch (preferred)

```bash
# Start governed OpenCode wave
dx-runner start --provider opencode --beads bd-123 --prompt-file /tmp/prompt.md

# Shared status/check/report API
dx-runner status --json
dx-runner check --beads bd-123 --json
dx-runner report --beads bd-123 --format json
```

### SSH Dispatch (BREAK-GLASS ONLY - dx-dispatch compat)

> ⚠️ **DEPRECATED**: `dx-dispatch` is a compatibility shim that forwards to `dx-runner` with deprecation warnings.
> Use `dx-runner start --provider opencode` for governed dispatch. Only use `dx-dispatch` for emergency cross-VM fanout when dx-runner direct dispatch is unavailable.

```bash
# BREAK-GLASS: Dispatch to canonical VMs (use epyc12, NOT epyc6)
dx-dispatch epyc12 "Run make test in ~/affordabot"
dx-dispatch macmini "Build the iOS app"
dx-dispatch homedesktop-wsl "Run integration tests"

# BREAK-GLASS: Check VM status
dx-dispatch --list

# BREAK-GLASS: Resume existing session
dx-dispatch epyc12 "Continue" --session ses_abc123

# BREAK-GLASS: Wait for completion
dx-dispatch epyc12 "Run tests" --wait --timeout 600
```

### Jules Cloud Dispatch (BREAK-GLASS - uses dx-dispatch shim)

```bash
# Dispatch Beads issue to Jules Cloud
dx-dispatch --jules --issue bd-123

# Dry run (preview prompt)
dx-dispatch --jules --issue bd-123 --dry-run
```

### Fleet Operations (BREAK-GLASS)

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
# BREAK-GLASS: dx-dispath with Slack notifications
dx-dispatch epyc12 "Run tests" --slack
```

Include in task prompt for completion notifications:
```
After completing, use slack_conversations_add_message
to post summary to channel C09MQGMFKDE.
```

## Migration from dx-dispatch

| dx-dispatch (deprecated) | dx-runner (canonical) |
|--------------------------|----------------------|
| `dx-dispatch epyc12 "task"` | `dx-runner start --provider opencode --beads bd-xxx --prompt-file /tmp/p.prompt` |
| `dx-dispatch --list` | `dx-runner status` |
| `dx-dispatch --status epyc12` | `dx-runner status --json` |

**Full Guide**

See [docs/MULTI_AGENT_COMMS.md](../../docs/MULTI_AGENT_COMMS.md)
