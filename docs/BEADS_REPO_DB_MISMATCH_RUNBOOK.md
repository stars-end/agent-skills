# Beads Repo/DB Mismatch Remediation Runbook

## Symptom

`bd show`, `bd status`, or `bd comments add` returns:

```
DATABASE MISMATCH DETECTED
Database repo ID: 08f75540
Current repo ID: fbeba79b
```

## Root Causes

| Cause | Description | Detection |
|-------|-------------|-----------|
| Copied `.beads` dir | `.beads/` copied from another repo/VM | `.beads/db-config.json` has different repo-id |
| Clone vs init | Repo cloned instead of initialized fresh | `git remote -v` shows different origin |
| Stale daemon | Beads daemon has cached old repo context | Daemon running with stale state |
| URL mismatch | Canonical URL changed but `.beads` not updated | `.beads/config.json` URL != git remote |

## Diagnosis Commands

```bash
# Check current repo ID from git
git rev-parse --show-toplevel 2>/dev/null && echo "Repo: $(basename $(git rev-parse --show-toplevel))"

# Check Beads database repo ID
cat .beads/db-config.json 2>/dev/null | jq -r '.repo_id // "missing"'

# Check canonical URL match
echo "Beads URL: $(cat .beads/config.json 2>/dev/null | jq -r '.canonical_url // "missing"')"
echo "Git remote: $(git remote get-url origin 2>/dev/null || echo 'none')"

# Check daemon status
bd daemon status 2>/dev/null || echo "Daemon status unknown"
```

## Remediation Steps

### Case 1: Copied `.beads` Directory (Most Common)

**Scenario**: Directory copied from another machine/VM.

**Steps**:

```bash
# 1. Backup existing Beads data (optional but recommended)
cp -r .beads .beads.backup.$(date +%Y%m%d%H%M%S)

# 2. Remove the mismatched .beads directory
rm -rf .beads

# 3. Re-initialize Beads for this repo
bd init

# 4. Verify connection
bd status
```

**Note**: This creates a new local database. Issues from the old database will NOT be migrated. If you need to preserve issues, export them first using `bd export` before removal.

### Case 2: Stale Daemon State

**Scenario**: Daemon was started when repo was in different state.

**Steps**:

```bash
# 1. Stop the daemon
bd daemon stop

# 2. Clear daemon cache (if applicable)
rm -rf ~/.cache/beads-daemon/* 2>/dev/null || true

# 3. Restart daemon
bd daemon start

# 4. Verify
bd status
```

### Case 3: URL Mismatch

**Scenario**: Git remote changed but Beads config not updated.

**Steps**:

```bash
# 1. Get current canonical URL
CURRENT_URL=$(git remote get-url origin)

# 2. Update Beads config
cat .beads/config.json | jq --arg url "$CURRENT_URL" '.canonical_url = $url' > .beads/config.json.tmp
mv .beads/config.json.tmp .beads/config.json

# 3. Re-sync
bd sync

# 4. Verify
bd status
```

### Case 4: Fresh VM Setup

**Scenario**: New VM, repo cloned from origin.

**Steps**:

```bash
# 1. Ensure you're in the repo root
cd ~/agent-skills  # or appropriate repo

# 2. Initialize fresh
bd init

# 3. Sync from remote
bd sync --force

# 4. Verify
bd status
```

## EPYC12 Specific Notes

For EPYC12, the canonical repos are:
- `~/agent-skills` (primary)
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

Each should have its own `.beads` directory initialized fresh on the VM.

**Quick fix for EPYC12**:

```bash
# For agent-skills
cd ~/agent-skills
rm -rf .beads
bd init
bd sync

# For prime-radiant-ai
cd ~/prime-radiant-ai
rm -rf .beads
bd init
bd sync
```

## Verification

After remediation, all commands should work:

```bash
# Should show repo status without mismatch warning
bd status

# Should show issue details
bd show <known-issue-id>

# Should add comment successfully
bd comments add <known-issue-id> "dx test"
```

## Evidence Collection Template

When remediating on a remote VM (e.g., EPYC12), collect this evidence:

### Before Remediation

```bash
# Record the mismatch error
echo "=== BEFORE REMEDIATION ===" > /tmp/beads-remediation-evidence.txt
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /tmp/beads-remediation-evidence.txt
echo "" >> /tmp/beads-remediation-evidence.txt

# Capture the mismatch error
echo "--- bd status output ---" >> /tmp/beads-remediation-evidence.txt
cd ~/agent-skills && bd status 2>&1 >> /tmp/beads-remediation-evidence.txt || true
echo "" >> /tmp/beads-remediation-evidence.txt

# Capture repo IDs
echo "--- Repo IDs ---" >> /tmp/beads-remediation-evidence.txt
echo "Git toplevel: $(cd ~/agent-skills && git rev-parse --show-toplevel)" >> /tmp/beads-remediation-evidence.txt
echo "Beads db-config.json repo_id: $(cd ~/agent-skills && cat .beads/db-config.json 2>/dev/null | jq -r '.repo_id // "missing"')" >> /tmp/beads-remediation-evidence.txt
echo "" >> /tmp/beads-remediation-evidence.txt

# Repeat for prime-radiant-ai
echo "--- prime-radiant-ai status ---" >> /tmp/beads-remediation-evidence.txt
cd ~/prime-radiant-ai && bd status 2>&1 >> /tmp/beads-remediation-evidence.txt || true
```

### Apply Remediation

```bash
# Apply the fix
cd ~/agent-skills && rm -rf .beads && bd init && bd sync
cd ~/prime-radiant-ai && rm -rf .beads && bd init && bd sync
```

### After Remediation

```bash
# Capture success evidence
echo "=== AFTER REMEDIATION ===" >> /tmp/beads-remediation-evidence.txt
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /tmp/beads-remediation-evidence.txt
echo "" >> /tmp/beads-remediation-evidence.txt

echo "--- agent-skills bd status ---" >> /tmp/beads-remediation-evidence.txt
cd ~/agent-skills && bd status 2>&1 >> /tmp/beads-remediation-evidence.txt
echo "" >> /tmp/beads-remediation-evidence.txt

echo "--- agent-skills bd show (first issue) ---" >> /tmp/beads-remediation-evidence.txt
cd ~/agent-skills && bd status --json 2>/dev/null | jq -r '.issues[0].id' | head -1 | xargs -I{} bd show {} 2>&1 >> /tmp/beads-remediation-evidence.txt || echo "No issues found" >> /tmp/beads-remediation-evidence.txt
echo "" >> /tmp/beads-remediation-evidence.txt

echo "--- prime-radiant-ai bd status ---" >> /tmp/beads-remediation-evidence.txt
cd ~/prime-radiant-ai && bd status 2>&1 >> /tmp/beads-remediation-evidence.txt

# Display evidence
cat /tmp/beads-remediation-evidence.txt
```

### Expected Successful Output

After remediation, `bd status` should show output like:
```
Project: agent-skills
Status: connected
Issues: 42 open
```

NOT:
```
DATABASE MISMATCH DETECTED
Database repo ID: 08f75540
Current repo ID: fbeba79b
```

## Prevention

1. **Never copy `.beads` directories** between VMs/repos
2. **Always run `bd init`** on fresh clones
3. **Use worktrees** for development (per AGENTS.md)
4. **Keep daemon running** for sync automation

## Related Files

- `~/agent-skills/AGENTS.md` - Canonical repo rules
- `.beads/config.json` - Repo configuration
- `.beads/db-config.json` - Database configuration
- `~/.config/beads/daemon.json` - Daemon configuration
