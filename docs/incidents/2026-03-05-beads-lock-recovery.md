# Beads Infrastructure Issues - Diagnostic Summary

**Date**: 2026-03-05
**Host**: fengning@3e8b85bbd2a8 (Linux)
**Beads Workspace**: `~/bd` (canonical Dolt server mode)
**Primary Repo**: `~/prime-radiant-ai`

---

## Executive Summary

Beads MCP tools are failing to execute due to database lock issues. The system falls back to direct mode, but direct mode also fails with "unable to open database file" errors. This blocks all issue tracking and workflow automation.

**Current State**: Non-functional
**Impact**: Cannot create, update, or query Beads issues
**Urgency**: High (blocking development workflow)

---

## Error Manifest

### Primary Error
```
Error calling tool 'create': bd command failed: 
Warning: Daemon took too long to start (>5s). Running in direct mode.
  Hint: Run 'bd doctor' to diagnose daemon issues
Error: failed to open database: failed to enable WAL mode: sqlite3: 
unable to open database file: open /home/fengning/bd/.beads/dolt: is a directory
```

### Secondary Error (Server Start)
```
Error: server started (PID 50001) but not accepting connections on port 3307: 
timeout after 10s waiting for server at 127.0.0.1:3307
Check logs: /home/fengning/bd/.beads/dolt-server.log
```

### Server Log Evidence
```
database "dolt" is locked by another dolt process; either clone the database 
to run a second server, or stop the dolt process which currently holds an 
exclusive write lock on the database
```
(Repeated 10+ times in logs)

---

## Diagnostic Output

### `bd doctor` Output
```
RUNTIME (2/3 passed)
  ⚠  Embedded Mode Concurrency: Embedded mode with 1 lock indicator(s) 
     — concurrent access may cause failures
      Detected: noms LOCK in dolt root (Dolt database lock). 
      Embedded mode is single-writer only.
      └─ Switch to server mode: bd dolt set mode server && bd dolt start

FEDERATION (4/5 passed)
  ⚠  Federation remotesapi: Server not running (1 peers configured)
      Federation requires dolt sql-server for peer sync
      └─ Start dolt sql-server in server mode to enable peer-to-peer sync

MAINTENANCE (9/11 passed)
  ⚠  Stale Molecules: 2 complete-but-unclosed molecule(s)
      Example: [bd-0e2 bd-8ybv]
  ⚠  Pending Migrations: 1 available
```

### `bd dolt test --json` Output
```json
{
  "connection_ok": true,
  "host": "100.107.173.83",
  "port": 3307
}
```
*Note: Connection test passes, but actual operations fail*

### File System State
```bash
$ ls -la ~/bd/.beads/
drwxr-xr-x  2 fengning fengning 4096 Mar  5 14:59 dolt/
# dolt is a DIRECTORY, not a file - this seems wrong

$ ls -la ~/bd/.beads/dolt/
-rw-r--r--  1 fengning fengning    0 Mar  5 14:59 noms LOCK
# Lock file exists
```

---

## What's Been Tried

### 1. Attempted Server Start
```bash
$ cd ~/bd && bd dolt start
Error: server started (PID 50001) but not accepting connections...
```

### 2. Mode Switch Attempt
```bash
$ bd dolt set mode server
Error: mode is no longer configurable; beads always uses server mode
```
*Note: Docs say mode is always server, but doctor recommends switching to server mode*

### 3. Multiple Daemon Restarts
- Daemon falls back to direct mode after 5s timeout
- Direct mode fails with database open error
- Pattern repeats on every MCP tool call

---

## Environment Details

### System
```
Host: 3e8b85bbd2a8 (Docker container or VM)
OS: Linux
User: fengning
Shell: /usr/bin/zsh
```

### Beads Installation
```
Workspace: ~/bd
Remote: stars-end/bd (canonical)
Backend: Dolt server mode (configured)
Actual Mode: Broken (daemon + direct both failing)
```

### Dolt Server Logs Location
```
/home/fengning/bd/.beads/dolt-server.log
```

### Active Processes
```bash
$ ps aux | grep -i "bd\|dolt\|beads"
# No obvious Beads/Dolt daemon processes running
# But lock file suggests process thinks it's running
```

---

## Root Cause Hypothesis

**Most Likely**: Stale lock file (`noms LOCK`) from previous unclean shutdown is blocking all database access.

**Evidence**:
1. `~/bd/.beads/dolt` is a directory containing `noms LOCK` file
2. Error says "database locked by another dolt process"
3. No active dolt process visible in `ps`
4. Connection test passes but operations fail

**Alternative**: Database corruption or incorrect file structure (`dolt` should be a file, not directory?)

---

## Expected Behavior

### Normal Operation
1. MCP tools call Beads CLI
2. Beads connects to Dolt server at `100.107.173.83:3307`
3. Operations complete successfully
4. Returns issue data

### Actual Behavior
1. MCP tools call Beads CLI
2. Daemon attempts start, times out after 5s
3. Falls back to direct mode
4. Direct mode fails: "unable to open database file"
5. Returns error to MCP tool
6. No operations complete

---

## Required Fix

### Immediate (Unblock)
1. **Remove stale lock file**: `rm ~/bd/.beads/dolt/noms\ LOCK`
2. **Verify database structure**: Is `~/bd/.beads/dolt` supposed to be a directory?
3. **Restart daemon**: Force clean restart
4. **Test with simple operation**: `bd list`

### Long-term (Stability)
1. **Add lock cleanup on startup**: Beads should auto-clean stale locks
2. **Better daemon supervision**: Systemd service? (already have `beads-dolt.service`)
3. **Health check integration**: Monitor should detect and auto-recover
4. **Document recovery procedure**: Add to runbook

---

## Impact Assessment

### Blocked Operations
- ❌ Creating new issues (epics/features/tasks)
- ❌ Updating issue status
- ❌ Querying ready work
- ❌ Tracking dependencies
- ❌ All Beads workflow automation

### Workaround Status
- ✅ Can work without Beads (use git + manual tracking)
- ✅ Can create markdown plans instead
- ⚠️ Loses automated tracking and dependency management

### Urgency
**High**: This is a core DX tool. Manual workarounds increase cognitive load and risk of lost work.

---

## Systemd Service Status

### Expected Service
```
systemctl --user status beads-dolt.service
```

**Question**: Is this service running? Should it be?

### Service Contract (from AGENTS.md)
> Linux canonical VMs: `systemctl --user is-active beads-dolt.service`

---

## Multi-VM Context

### Canonical Hosts
- macmini (macOS)
- homedesktop-wsl (WSL)
- epyc6 (Linux) - **DISABLED per AGENTS.md**
- epyc12 (Linux)
- Current: 3e8b85bbd2a8 (Linux, Docker?)

### Federation
- 1 peer configured
- Federation requires running dolt sql-server
- Currently not running

---

## Success Criteria for Fix

### Immediate
- [ ] `bd list` returns successfully
- [ ] `bd create` works
- [ ] `bd show <id>` works
- [ ] No "daemon took too long" warnings
- [ ] No "database locked" errors

### Validation
- [ ] Create test issue via MCP tool
- [ ] Query test issue via `bd show`
- [ ] Close test issue
- [ ] All operations complete <2s

---

## Questions for Infra Agent

1. **Lock File**: Should I delete `~/bd/.beads/dolt/noms LOCK`? Is it safe?
2. **Directory Structure**: Should `~/bd/.beads/dolt` be a file or directory?
3. **Service**: Should `beads-dolt.service` be running? How to check?
4. **Server**: Is the remote server at `100.107.173.83:3307` actually accessible?
5. **Recovery**: What's the canonical recovery procedure for this state?
6. **Prevention**: How to prevent this from recurring?

---

## Reference Documentation

- `~/agent-skills/docs/PRIME_RADIANT_BEADS_DOLT_RUNBOOK.md` (canonical runbook)
- AGENTS.md (Section 1.5: Canonical Beads Contract)
- `~/.agents/skills/bd-doctor/SKILL.md`
- `~/.agents/skills/beads-dolt-fleet/SKILL.md`

---

## Next Steps

1. **Diagnose**: Run full diagnostic suite
2. **Recover**: Apply safe recovery procedure
3. **Validate**: Test with simple operations
4. **Document**: Update runbook with recovery steps
5. **Prevent**: Add monitoring/auto-recovery

---

**Agent Assignment**: Infrastructure/DevOps engineer with Dolt + Beads expertise
**Priority**: P0 (blocking development workflow)
**SLA**: Immediate (within current session)
