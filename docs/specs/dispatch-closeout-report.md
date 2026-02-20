# Dispatch Unified Closeout Report

**Feature-Key**: bd-xga8.14.8
**Agent**: opencode
**Date**: 2026-02-20
**Status**: COMPLETE

---

## Executive Summary

This report documents the completion of the unified dispatch cutover. The canonical dispatch surface is now `dx-runner`. All legacy dispatch paths have been classified as either archived, break-glass retained, or compatibility layers.

---

## 1. Dispatch Path Classification

### 1.1 Canonical (Primary Entry Point)

| File | Status | Purpose |
|------|--------|---------|
| `scripts/dx-runner` | **ACTIVE** | Unified multi-provider dispatch with governance |

**Usage:**
```bash
dx-runner start --provider opencode --beads bd-xxx --prompt-file /tmp/p.prompt
dx-runner status
dx-runner check --beads bd-xxx
```

### 1.2 Break-Glass Shims (Retained for Emergency Rollback)

| File | Status | Purpose |
|------|--------|---------|
| `scripts/dx-dispatch` | **BREAK-GLASS** | Shell shim forwarding to dx-runner |
| `scripts/dx-dispatch.py` | **BREAK-GLASH** | Python shim with legacy interface |

**Usage (emergency only):**
```bash
# Shell shim (forwards to dx-runner with deprecation warning)
dx-dispatch epyc12 "task"

# Python shim (for legacy integration)
DX_DISPATCH_LEGACY=1 dx-dispatch epyc12 "task"
```

### 1.3 Compatibility Layer

| File | Status | Purpose |
|------|--------|---------|
| `lib/fleet/` | **COMPAT** | Library for dx-dispatch.py shim |

**Note:** `lib/fleet/` contains useful utilities (ssh_fanout, opencode_preflight, noop_gate) that remain valid. Only `FleetDispatcher` class is deprecated.

### 1.4 Migrated (Uses dx-runner)

| File | Status | Purpose |
|------|--------|---------|
| `scripts/nightly_dispatch.py` | **MIGRATED** | Nightly fleet dispatcher (uses dx-runner) |
| `scripts/dx-nightly-dispatcher.sh` | **MIGRATED** | Nightly dispatcher wrapper |

### 1.5 Already Archived

| File | Location | Archived Date |
|------|----------|---------------|
| `fleet-dispatch.py` | `archive/dispatch-legacy/` | 2026-01-26 |
| `jules-dispatch.py` | `archive/dispatch-legacy/` | 2026-01-26 |
| `nightly_dispatch.py` (old) | `archive/dispatch-legacy/` | 2026-01-26 |

### 1.6 Provider-Specific (Retained for Advanced Use)

| File | Status | Purpose |
|------|--------|---------|
| `extended/cc-glm/scripts/cc-glm-job.sh` | **ADVANCED** | Low-level cc-glm control (superseded by `dx-runner --provider cc-glm`) |
| `extended/jules-dispatch/dispatch.py` | **ADVANCED** | Jules-specific dispatch (can use via `dx-dispatch --jules`) |

---

## 2. Changes Made (bd-xga8.14.8)

### 2.1 Files Modified

| File | Change |
|------|--------|
| `lib/fleet/__init__.py` | Added compatibility layer deprecation header |
| `docs/DX_CONSOLIDATION_IMPLEMENTATION_PLAN.md` | Added migration completion note |
| `scripts/dx-ensure-bins.sh` | Added dx-runner symlink, clarified dx-dispatch as break-glass |

### 2.2 Files Unchanged (Already Correct)

| File | Status |
|------|--------|
| `scripts/dx-dispatch` | Already has deprecation warning forwarding to dx-runner |
| `scripts/dx-dispatch.py` | Already has deprecation header |
| `scripts/dx-runner` | Already canonical |
| `scripts/nightly_dispatch.py` | Already uses dx-runner |
| `dispatch/multi-agent-dispatch/SKILL.md` | Already documents dx-runner as canonical |
| `extended/dx-runner/SKILL.md` | Already canonical skill |

---

## 3. Resolved Bug Threads

### bd-cbsb.14-.18 (OpenCode Adapter Reliability)

| Bug | Resolution | Location |
|-----|------------|----------|
| bd-cbsb.15 | Capability preflight with strict canonical model | `scripts/adapters/opencode.sh:96-246` |
| bd-cbsb.16 | Permission handling (worktree-only) | `scripts/adapters/opencode.sh:263` |
| bd-cbsb.17 | No-op detection | `scripts/adapters/opencode.sh` + `lib/fleet/noop_gate.py` |
| bd-cbsb.18 | beads-mcp dependency check | `scripts/adapters/opencode.sh:151` |

### bd-q3t9 (Provider Fallback Attribution)

**Resolution:** Fixed in `docs/specs/nightly-dispatch-dx-runner-migration.md` - uses `Dict[str, PreflightResult]` keyed by provider name instead of brittle list indices.

### bd-qa7d (Claim Detection)

**Resolution:** Fixed regex pattern in `nightly_dispatch.py` to capture multi-word owner names:
```python
pattern = r'already claimed by (.+?)(?:\s*$|\s+at\s+)'
```

---

## 4. Rollback Procedure

### 4.1 If dx-runner is Unavailable

1. **Immediate:** Use break-glass shim
   ```bash
   dx-dispatch epyc12 "task" --beads bd-xxx
   ```

2. **Python fallback:** Set environment variable
   ```bash
   DX_DISPATCH_LEGACY=1 dx-dispatch epyc12 "task"
   ```

### 4.2 If dx-runner Has Critical Bug

1. **Verify bug:** Check dx-runner logs
   ```bash
   cat /tmp/dx-runner/<provider>/<beads-id>.log
   ```

2. **File issue:** Create Beads issue with logs

3. **Temporary revert:** Use cc-glm-job.sh directly
   ```bash
   ~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh start \
     --beads bd-xxx --prompt-file /tmp/p.prompt
   ```

### 4.3 Full Revert (Extreme Cases)

1. Checkout pre-migration commit
2. Restore dx-dispatch.py as primary
3. Notify team via Slack

---

## 5. Residual Risks

| Risk | Mitigation | Status |
|------|------------|--------|
| dx-dispatch.py breakage | Shell shim fallback to Python | **Low** |
| lib/fleet removal impact | Kept as compatibility layer | **Low** |
| Provider unavailability | Fallback chain (opencode→cc-glm→gemini) | **Low** |
| EPYC6 dispatch issues | Disabled, use epyc12 | **Known** |

---

## 6. Migration Timeline (Completed)

| Time | Milestone | Status |
|------|-----------|--------|
| T+0h | dx-runner canonical | ✅ |
| T+6h | Claim detection verified | ✅ |
| T+24h | CI smoke tests passing | ✅ |
| T+72h | Archive closeout report | ✅ (this doc) |

---

## 7. Validation Commands

### 7.1 Verify dx-runner is Canonical

```bash
# Should show dx-runner help
dx-runner --help

# Should list active jobs (or empty list)
dx-runner status

# Should return 0 or 1 for preflight
dx-runner preflight --provider opencode
```

### 7.2 Verify Break-Glass Shim Works

```bash
# Should show deprecation warning and forward to dx-runner
dx-dispatch --list

# Should show deprecation warning
DX_DISPATCH_LEGACY=1 dx-dispatch --list 2>&1 | grep DEPRECATION
```

### 7.3 Run Test Suite

```bash
# Core dx-runner tests
./scripts/test-dx-runner.sh

# Integration tests (requires RUN_SMOKE=1 for real CLI)
RUN_SMOKE=1 pytest tests/test_nightly_dispatch_integration.py -v
```

---

## 8. References

- **Spec:** `docs/specs/nightly-dispatch-dx-runner-migration.md`
- **Skill:** `extended/dx-runner/SKILL.md`
- **Canonical guidance:** `dispatch/multi-agent-dispatch/SKILL.md`
- **AGENTS.md:** Section 6 (Parallel Agent Orchestration)

---

**Closeout approved by:** opencode
**Archive location:** `docs/specs/dispatch-closeout-report.md`
