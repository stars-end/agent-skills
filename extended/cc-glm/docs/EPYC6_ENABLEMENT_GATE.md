# EPYC6 Enablement Gate

> Status: **DISABLED** (default until gate explicitly passed)
> Last Updated: 2026-02-18
> Related: bd-xga8.1.3, DX_FLEET_SPEC_V8.md

## Current State

EPYC6 is **disabled for cc-glm dispatch** pending resolution of runtime and session issues.

**Default Target:** Use `epyc12` as the Linux dispatch target until this gate is explicitly passed.

## Why EPYC6 Is Disabled

| Issue | Description | Impact |
|-------|-------------|--------|
| Runtime errors | OpenCode session failures on epyc6 | Dispatch fails mid-task |
| Session persistence | Sessions not resuming correctly | Lost work, duplicate effort |
| Network path | Requires jump host from some VMs | Higher latency, more failure points |
| Tool gaps | Missing `jq` (no sudo access) | Scripts requiring jq fail |

## Preflight Checks (Must ALL Pass)

Run these checks before enabling epyc6 for dispatch:

### 1. SSH Connectivity

```bash
# From dispatcher VM (usually homedesktop-wsl or macmini)
ssh -o ConnectTimeout=10 feng@epyc6 "echo 'SSH OK'"

# Expected: "SSH OK" printed within 10 seconds
# Fail: Timeout, connection refused, or authentication error
```

**Pass criteria:** Direct SSH works without jump host for dispatcher VM.

### 2. OpenCode Health

```bash
# On epyc6
opencode health

# Expected: Healthy status
# Fail: Error messages, unhealthy status, or command not found
```

**Pass criteria:** `opencode health` returns healthy status.

### 3. Session Resume Test

```bash
# On epyc6: Create test session
SESSION=$(opencode session create --name "epyc6-gate-test" 2>&1 | grep -o 'ses_[a-zA-Z0-9]*' | head -1)
echo "Created session: $SESSION"

# Send test prompt
opencode session prompt "$SESSION" "Reply with the word CONFIRMED only"

# Wait 30 seconds, then resume
sleep 30
opencode session prompt "$SESSION" "What was your previous instruction?"

# Check for session continuity
# Expected: Agent recalls previous instruction
# Fail: Agent has no memory of previous prompt
```

**Pass criteria:** Session persists and recalls context after 30+ seconds.

### 4. Dispatch Round-Trip

```bash
# From dispatcher VM
dx-dispatch epyc6 "Create a file /tmp/epyc6-gate-test.txt with content 'GATE_PASSED'"

# Wait 2 minutes, then verify
sleep 120
ssh feng@epyc6 "cat /tmp/epyc6-gate-test.txt"

# Expected: "GATE_PASSED"
# Fail: File missing, wrong content, or dispatch failed
```

**Pass criteria:** Task completes successfully, file created with correct content.

### 5. Tool Availability

```bash
# On epyc6
which jq || echo "jq NOT FOUND (expected)"

# Scripts must use grep-based JSON parsing
# Verify that dx-dispatch works without jq
dx-dispatch --status epyc6

# Expected: Status returned successfully
# Fail: jq-related errors
```

**Pass criteria:** All required tools available; scripts handle missing jq gracefully.

## Acceptance Checklist

Before enabling epyc6, the operator MUST verify:

```markdown
## EPYC6 Enablement Checklist
Date: _______________
Operator: _______________

### Preflight Checks
- [ ] SSH connectivity: Direct SSH works from dispatcher VM
- [ ] OpenCode health: `opencode health` returns healthy
- [ ] Session resume: Test session persists after 30+ seconds
- [ ] Dispatch round-trip: Test dispatch completes successfully
- [ ] Tool availability: Required tools present, jq absence handled

### Documentation Updated
- [ ] fleet_hosts.yaml notes updated
- [ ] CANONICAL_TARGETS.md updated (if needed)
- [ ] DX_FLEET_SPEC_V8.md updated (if adding to rollout)

### Rollback Plan Documented
- [ ] Procedure to disable epyc6 if issues recur
- [ ] Contact/responsibility defined

### Sign-off
- [ ] All preflight checks passed
- [ ] Ready to enable epyc6 for dispatch
```

## How To Enable EPYC6

After passing ALL preflight checks and completing the acceptance checklist:

1. Update `extended/cc-glm/docs/EPYC6_ENABLEMENT_GATE.md`:
   - Change status from `DISABLED` to `ENABLED`
   - Add enablement date and operator

2. Update dispatch defaults (if applicable):
   - Update `CANONICAL_VM_LINUX2` references if switching from epyc12

3. Document in Beads:
   - Close enablement issue with evidence
   - Reference passing test results

## Rollback Procedure

If issues recur after enabling:

```bash
# 1. Mark EPYC6 as disabled in this file
# 2. Redirect dispatches to epyc12
# 3. Document failure mode in this file's "Known Issues" section

# Immediate dispatch fallback
dx-dispatch epyc12 "Your task here"  # instead of epyc6
```

## Known Issues

| Issue | Status | Workaround |
|-------|--------|------------|
| Runtime errors | Investigating | Use epyc12 |
| Session persistence | Investigating | Use epyc12 |
| jq missing | Permanent | Scripts use grep-based parsing |

## Related Files

- `configs/fleet_hosts.yaml` - Host registry
- `scripts/canonical-targets.sh` - VM environment variables
- `docs/DX_FLEET_SPEC_V8.md` - Fleet rollout status
- `docs/CANONICAL_TARGETS.md` - Canonical VM documentation
- `dispatch/multi-agent-dispatch/SKILL.md` - Dispatch skill
