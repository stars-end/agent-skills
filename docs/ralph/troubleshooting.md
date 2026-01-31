# Ralph Troubleshooting Guide

This guide helps you diagnose and resolve common issues when working with Ralph.

## Debug Mode

Enable verbose logging for debugging:

```bash
# Export debug flag
export RALPH_DEBUG=1

# Or set per-command
RALPH_DEBUG=1 ralph [command]
```

Debug mode provides:
- Detailed execution trace
- File operation logs
- Agent communication details
- State transition information

---

## Common Errors and Solutions

### Error: `RALPH_TASK.md not found`

**Cause**: Ralph initialized in wrong directory or task file deleted.

**Solution**:
```bash
# Check current directory
pwd

# Re-initialize if needed
cd /path/to/correct/directory
# Ensure RALPH_TASK.md exists
```

**Debug tip**: Run `RALPH_DEBUG=1 ralph` to see where Ralph is searching for the task file.

---

### Error: `Agent not found: <agent-name>`

**Cause**: Agent not configured in `/Users/fengning/agent-skills/AGENTS.md`.

**Solution**:
1. Check available agents:
```bash
cat /Users/fengning/agent-skills/AGENTS.md
```

2. Add agent configuration if missing:
```markdown
### <agent-name>
- Model: <model-name>
- Tools: <tools-list>
- Description: <description>
```

**Debug tip**: Verify agent name spelling matches exactly.

---

### Error: `Cannot read task: permission denied`

**Cause**: File permissions issue on `RALPH_TASK.md`.

**Solution**:
```bash
# Check permissions
ls -la RALPH_TASK.md

# Fix permissions
chmod 644 RALPH_TASK.md
```

**Debug tip**: Check if file is owned by correct user with `ls -l RALPH_TASK.md`.

---

### Error: `No unchecked criteria remaining`

**Cause**: All tasks in `RALPH_TASK.md` are completed.

**Solution**:
- Verify task completion by checking `[x]` markers
- If work remaining, add unmarked criteria
- If truly complete, close Ralph session

**Debug tip**: Use `grep -c "^\- \[" RALPH_TASK.md` to count remaining tasks.

---

### Error: `Git repository required`

**Cause**: Working directory not a git repository or `.git` missing.

**Solution**:
```bash
# Initialize git if needed
git init

# Or ensure you're in the correct repo
cd /path/to/git/repo
```

**Debug tip**: Check with `git status` to verify repository state.

---

## Recovering from Failures

### Agent Crashes or Hangs

**Immediate action**:
```bash
# Kill stuck agent (replace <pid> with actual process ID)
kill <pid>

# Or force kill if needed
kill -9 <pid>
```

**Recovery**:
1. Check work completed before crash:
```bash
git diff
```

2. Commit completed work if appropriate:
```bash
git add .
git commit -m "WIP: Recovered from crash"
```

3. Resume with Ralph:
```bash
ralph
```

**Debug tip**: Check agent logs for crash context in `RALPH_DEBUG=1` output.

---

### Incomplete File Operations

**Symptoms**: Files created but missing content, or partial changes.

**Recovery**:
1. Check last successful operation:
```bash
git log -1 --stat
```

2. Verify file integrity:
```bash
wc -l <filename>
```

3. Manually complete if needed:
```bash
# Add missing content
echo "content" >> <filename>
```

**Debug tip**: Use `git diff HEAD` to see what was last attempted.

---

### State Corruption

**Symptoms**: Ralph unable to determine task state, repeated errors.

**Recovery**:
```bash
# Backup current state
cp RALPH_TASK.md RALPH_TASK.md.backup

# Manually fix [ ] markers
# Then continue
ralph
```

**Debug tip**: Validate task file format with `RALPH_DEBUG=1 ralph`.

---

## Resuming Interrupted Runs

### After System Reboot or Shutdown

**Steps**:
1. Navigate to working directory:
```bash
cd /path/to/.ralph-work-xxxxx
```

2. Check git status:
```bash
git status
```

3. Commit any uncommitted changes:
```bash
git add .
git commit -m "WIP: Recovered after interruption"
```

4. Resume Ralph:
```bash
ralph
```

**Debug tip**: Check `RALPH_TASK.md` to see which criteria were last processed.

---

### After Network Interruption

**Steps**:
1. Verify git remote is accessible:
```bash
git remote -v
git ls-remote origin
```

2. Pull latest changes if needed:
```bash
git pull --rebase
```

3. Resume Ralph:
```bash
ralph
```

**Debug tip**: Use `RALPH_DEBUG=1` to see network-related log messages.

---

### After Manual Intervention

**Steps**:
1. Check what you changed:
```bash
git diff
```

2. Stage your changes:
```bash
git add .
```

3. Resume Ralph:
```bash
ralph
```

**Debug tip**: Ralph will continue from the next unchecked criterion.

---

## Orphaned OpenCode Session Cleanup

### Identifying Orphaned Sessions

OpenCode sessions may become orphaned if:
- Agent crashes unexpectedly
- Process killed with SIGKILL
- System shutdown during session

**Check for orphaned sessions**:
```bash
# Look for OpenCode processes
ps aux | grep -i opencode

# Check for temporary session files
ls -la ~/.opencode/sessions/
ls -la /tmp/opencode-*
```

---

### Cleaning Up Orphaned Sessions

**Safe cleanup procedure**:

1. **Identify session IDs**:
```bash
# Find session directories
find ~/.opencode -type d -name "session-*"
```

2. **Kill orphaned processes**:
```bash
# Terminate safely first
pkill -TERM opencode

# Wait 5 seconds, then force kill if needed
sleep 5
pkill -KILL opencode
```

3. **Remove session artifacts**:
```bash
# Remove specific session (replace <session-id>)
rm -rf ~/.opencode/sessions/<session-id>

# Or clean all old sessions (>24 hours)
find ~/.opencode/sessions -type d -mtime +1 -exec rm -rf {} +
```

4. **Clean temporary files**:
```bash
rm -f /tmp/opencode-*
```

**Debug tip**: Use `RALPH_DEBUG=1` before cleanup to log session IDs being removed.

---

### Preventing Orphaned Sessions

1. **Use proper shutdown**:
   - Always exit Ralph cleanly
   - Don't use `kill -9` on Ralph agents

2. **Session timeout**:
   - Configure auto-cleanup for inactive sessions
   - Monitor long-running sessions

3. **Health checks**:
   ```bash
   # Add to crontab for daily cleanup
   0 3 * * * find ~/.opencode/sessions -type d -mtime +2 -exec rm -rf {} +
   ```

**Debug tip**: Monitor session count with `ls ~/.opencode/sessions | wc -l`.

---

## Beads Database Issues

### Database Lock Errors

**Symptoms**:
- "database is locked" error
- Unable to read/write issues
- Commands hang indefinitely

**Causes**:
- Another Beads process running
- Previous crash left lock file
- Concurrent access

**Solutions**:

1. **Check for running processes**:
```bash
ps aux | grep -i beads
ps aux | grep -i "bd "
```

2. **Wait and retry** (if another process is running):
```bash
# Wait 30 seconds
sleep 30
bd list
```

3. **Force release lock** (only if no other processes):
```bash
# Check lock file location
bd --help | grep -i database

# Remove lock file manually
rm -f ~/.beads/*.lock
# Or
rm -f /path/to/.beads/*.lock
```

4. **Database integrity check**:
```bash
cd /path/to/workspace
bd doctor
```

**Debug tip**: Use `RALPH_DEBUG=1 bd <command>` to see database operations.

---

### Database Corruption

**Symptoms**:
- "database disk image is malformed"
- Commands return unexpected results
- Issue data missing or incorrect

**Solutions**:

1. **Backup current database**:
```bash
cd /path/to/workspace
cp .beads/issues.db .beads/issues.db.backup
```

2. **Export to JSONL** (if possible):
```bash
bd export -o .beads/issues-backup.jsonl
```

3. **Rebuild database**:
```bash
# Remove corrupted database
rm .beads/issues.db

# Reinitialize Beads
bd init --force

# Import from backup if available
# (Manual import may be required)
```

4. **Sync from remote** (if using sync):
```bash
bd sync --force
```

**Debug tip**: Check database file size with `ls -lh .beads/issues.db` (should not be zero).

---

### Sync Conflicts

**Symptoms**:
- "Merge conflict" during `bd sync`
- Duplicate issue IDs
- Inconsistent state between local and remote

**Solutions**:

1. **Check conflict status**:
```bash
cd /path/to/workspace
bd sync --dry-run
```

2. **Manual conflict resolution**:
```bash
# View JSONL file
cat .beads/issues.jsonl

# Edit to resolve conflicts
# Keep your version, remote version, or merge
vim .beads/issues.jsonl
```

3. **Force local or remote**:
```bash
# Force local (discard remote)
bd sync --force-local

# Or force remote (pull from remote)
bd sync --force-remote
```

4. **Reinitialize if necessary**:
```bash
rm .beads/issues.jsonl
bd sync
```

**Debug tip**: Use `jq '.' .beads/issues.jsonl` to pretty-print for easier conflict resolution.

---

### Missing or Incorrect Issue Dependencies

**Symptoms**:
- Issues blocked by non-existent dependencies
- Circular dependency errors
- `bd ready` returns incorrect results

**Solutions**:

1. **Audit dependencies**:
```bash
# Check all dependencies
bd list | jq -r '.[] | "\(.id): \(.deps // [])"'

# Find circular dependencies
bd show <issue-id>
```

2. **Remove broken dependencies**:
```bash
bd update <issue-id> --deps []
```

3. **Rebuild dependency graph**:
```bash
# Export, fix, re-import
bd export -o /tmp/issues.jsonl
# Edit /tmp/issues.jsonl
bd import /tmp/issues.jsonl
```

**Debug tip**: Use `bd doctor` to run dependency consistency checks.

---

### Performance Issues

**Symptoms**:
- Slow `bd list` or `bd ready` commands
- Database operations timeout
- High CPU/memory usage

**Solutions**:

1. **Check database size**:
```bash
ls -lh .beads/issues.db
du -sh .beads/
```

2. **Archive old closed issues**:
```bash
# Export closed issues
bd list --status closed -o /tmp/closed-issues.jsonl

# Remove from database (careful!)
bd close <issue-id> --archive
```

3. **Vacuum database**:
```bash
cd /path/to/workspace
sqlite3 .beads/issues.db "VACUUM;"
```

4. **Rebuild indexes**:
```bash
sqlite3 .beads/issues.db "REINDEX;"
```

**Debug tip**: Use `sqlite3 .beads/issues.db ".schema"` to check index structure.

---

## General Debugging Tips

### Enable Verbose Logging

Always enable debug mode when troubleshooting:
```bash
RALPH_DEBUG=1 ralph
RALPH_DEBUG=1 bd <command>
```

### Check Git State

Before any troubleshooting:
```bash
git status
git log --oneline -5
```

### Verify File Integrity

Check that critical files exist and are valid:
```bash
# Check task file
test -f RALPH_TASK.md && echo "OK" || echo "MISSING"

# Check Beads database
test -f .beads/issues.db && echo "OK" || echo "MISSING"
```

### Use Tools for Diagnostics

- `strace` / `dtruss`: Trace system calls
- `lsof`: Check open files
- `ps`: Process status
- `jq`: JSON pretty-printing

### Log Collection

Create log file for debugging:
```bash
RALPH_DEBUG=1 ralph 2>&1 | tee ralph-debug.log
```

---

## Getting Help

If issues persist after trying these solutions:

1. **Collect diagnostic information**:
```bash
ralph --version
git --version
bd --version
cat RALPH_TASK.md
RALPH_DEBUG=1 ralph > debug.log 2>&1
```

2. **Check known issues**:
```bash
# Search in repo
cd ~/agent-skills
git log --all --grep="troubleshooting"
```

3. **Create a minimal reproducible case**:
   - Clean working directory
   - Minimal task file
   - Clear error reproduction steps

---

## Quick Reference

| Issue | Command | Notes |
|-------|---------|-------|
| Debug mode | `RALPH_DEBUG=1 ralph` | Enable verbose logging |
| Git status | `git status` | Check repository state |
| Beads sync | `bd sync` | Pull latest changes |
| Remove lock | `rm -f .beads/*.lock` | If no other processes |
| Kill agent | `kill <pid>` | Or `kill -9 <pid>` if stuck |
| Resume | `ralph` | After interruption |
| Doctor | `bd doctor` | Database health check |

