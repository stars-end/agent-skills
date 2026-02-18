# DX V8.x Compatibility Hardening: Evidence Table

**Generated**: 2026-02-17
**Source**: bd-xga8.11, cc-glm-headless-issues-log-2026-02-17.md
**Status**: Implementation in progress

---

## 1) Evidence Table

| Issue Pattern | Exact Command/Log Proof | Root Cause | V8 Rule Impacted |
|---------------|------------------------|------------|------------------|
| **Startup no-output ambiguity** | `status=running`, `log bytes=0` for 3+ min on bd-xga8.10.3, .4, .5, .8 | PTY wrapper buffers output until claude produces first token; no early heartbeat emitted | V8.3 monitoring (2 signals) |
| **Model selection drift** | Dispatch set `CC_GLM_MODEL=glm-5`, live process shows `--model glm-4.7` | Restart path doesn't persist effective model; env not captured in metadata | V8.3 delegation contract |
| **Hidden mutation with empty log** | bd-xga8.10.5/.8 worktrees have uncommitted changes despite 0-byte logs | Process can make file changes before first stdout write; log growth not reliable mutation signal | V8.3 atomic commits |
| **False stall from log-based health** | `health --stall-minutes 3` reports `stalled` when CPU time increasing | Health check only inspects log mtime/size, ignores process-level progress | V8.3 restart policy |
| **Restart destroys forensics** | `: > "$LOG_FILE"` in restart_cmd erases first-failure output | No log rotation; immediate truncation | V8.3 debuggability |
| **No exit code in terminal state** | `state=exited` but no distinction between success/crash | Exit code not persisted to metadata | V8.3 verification |
| **Watchdog conflicts with manual orchestration** | Watchdog restarted streams during manual supervision | No execution mode lock/mutex | V8.3 operator safety |

---

## 2) Minimal Fix Plan (Ranked by Risk Reduction)

### P0: Startup Observability + Progress Signals
1. **Startup heartbeat in cc-glm-headless.sh** - Write `LAUNCH_OK ts=... model=... pid=...` to stderr immediately
2. **Process-aware health** - Add CPU time check as secondary health signal
3. **Mutation marker** - Track worktree file changes via `.mutation` state file

### P1: Restart Contract Integrity
4. **Persist runtime contract** - Record model/auth_source to metadata on start
5. **Log rotation on restart** - `.log.1`, `.log.2` instead of truncation
6. **Exit code capture** - Persist exit code to metadata on termination

### P2: Operator Guardrails
7. **Preflight check** - Token resolved, model selected, claude reachable before long run
8. **Execution mode lock** - `.orchestrator-lock` file to disable watchdog auto-restart

---

## 3) Implementation Status

| Fix | Status | Files Changed |
|-----|--------|---------------|
| Startup heartbeat | DONE | cc-glm-headless.sh (V2.2) |
| Progress-aware health | DONE | cc-glm-job.sh (V3.0) |
| Mutation marker | DONE | cc-glm-job.sh (V3.3) |
| Runtime contract persistence | DONE | cc-glm-job.sh (V3.0) |
| Log rotation | DONE | cc-glm-job.sh (V3.0) |
| Exit code capture | DONE | cc-glm-job.sh (V3.1) |
| Preflight check | DONE | cc-glm-job.sh (V3.3) |
| SKILL.md runbook update | DONE | SKILL.md |
| Deterministic tests | DONE | test-cc-glm-job-v33.sh |

---

## 4) Validation Commands

```bash
# Test startup heartbeat
cc-glm-headless.sh --prompt "echo hello" 2>&1 | head -1
# Expected: [cc-glm-headless] LAUNCH_OK ...

# Test process-aware health
cc-glm-job.sh health --verbose --beads bd-test

# Test mutation marker
cc-glm-job.sh status --beads bd-test
# Shows: mutations=N in output

# Test log rotation on restart
cc-glm-job.sh start --beads bd-test --prompt-file /tmp/test.prompt
cc-glm-job.sh restart --beads bd-test
ls /tmp/cc-glm-jobs/bd-test.log.*
# Expected: bd-test.log.1 exists
```

---

## 5) Detection + Recovery Runbook

### Symptom: `running` + 0-byte log + age > threshold

**Detection**:
```bash
cc-glm-job.sh health --verbose --beads <id>
# Look for: health=healthy (process_active=true, cpu_time=N)
```

**Recovery**:
```bash
# Check if process is making progress (CPU time increasing)
ps -p $(cat /tmp/cc-glm-jobs/<id>.pid) -o pid,etime,cpu

# If CPU NOT increasing after 2 checks (30s apart):
cc-glm-job.sh restart --beads <id> --pty
```

### Symptom: Model drift on restart

**Detection**:
```bash
cc-glm-job.sh status --beads <id>
# Check: effective_model matches expected
```

**Recovery**:
```bash
# Explicit model on restart
CC_GLM_MODEL=glm-5 cc-glm-job.sh restart --beads <id> --pty
```

### Symptom: Hidden mutations with empty log

**Detection**:
```bash
cc-glm-job.sh status --beads <id>
# Check: mutations=N
```

**Recovery**:
```bash
# Inspect worktree
cd $(cat /tmp/cc-glm-jobs/<id>.meta | grep worktree | cut -d= -f2)
git status
git diff
```
