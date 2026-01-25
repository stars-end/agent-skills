# One-Shot Development Prompt: Infra Fix + Auto-Checkpoint

**Engineer:** Full-stack developer at fintech startup
**Date:** 2026-01-24
**Estimated Time:** 2-3 hours (including verification)

---

## Execution Summary

| Phase | Epic | Tasks | Coverage |
|-------|------|-------|----------|
| 1 | agent-skills-5f2 | 5f2.1, 5f2.2, 5f2.4 | Deploy 3 service accounts, add restart rate limiting, restart services |
| 2 | agent-skills-tis | tis.1, tis.2, tis.3, tis.4, tis.5 | Secret cache, auto-checkpoint.sh, GLM integration, cron, testing |

**Critical:** Complete Phase 1 before starting Phase 2.

---

## Phase 1: Infrastructure Fix (P0)

**Epic:** `agent-skills-5f2` - 1Password Service Accounts + Restart Rate Limiting

### Task 5f2.1: Create 3 Service Accounts (1Password)

**Prerequisites:**
- 1Password Business account access
- `op` CLI installed

**Steps:**

```bash
# 1. Create service account for opencode-cleanup (homedesktop-wsl)
# Purpose: Delete stale OpenCode sessions (Tier 2 - low risk)
op service-account create --vault "Dev" --accounts "opencode-cleanup" --description "OpenCode session cleanup service account"

# 2. Create service account for auto-checkpoint (all VMs)
# Purpose: Generate commit messages via GLM-4.5 (Tier 2 - low risk)
op service-account create --vault "Dev" --accounts "auto-checkpoint" --description "Auto-checkpoint GLM commit message generation"

# 3. Create service account for dx-dispatch (epyc6 only)
# Purpose: SSH dispatch to other VMs (Tier 1 - higher risk)
op service-account create --vault "Dev" --accounts "dx-dispatch" --description "Multi-VM dispatch service account"

# 4. Export tokens and save securely
# NOTE: Do this immediately after creation - tokens are only shown once!
# Copy each token directly from 1Password UI (don't write to disk)

# For each service account, click "Download token file" or copy the token
# Save each token to: ~/.config/systemd/user/<service-account>-token
```

**Per-VM Token Distribution:**

```bash
# === homedesktop-wsl ===
# Token needed: opencode-cleanup
mkdir -p ~/.config/systemd/user
chmod 700 ~/.config/systemd/user
# Paste token from 1Password
cat > ~/.config/systemd/user/opencode-cleanup-token << 'EOF'
PASTE_YOUR_TOKEN_HERE
EOF
chmod 600 ~/.config/systemd/user/opencode-cleanup-token

# === macmini ===
# Token needed: auto-checkpoint
mkdir -p ~/.config/systemd/user
chmod 700 ~/.config/systemd/user
cat > ~/.config/systemd/user/auto-checkpoint-token << 'EOF'
PASTE_YOUR_TOKEN_HERE
EOF
chmod 600 ~/.config/systemd/user/auto-checkpoint-token

# === epyc6 ===
# Tokens needed: auto-checkpoint, dx-dispatch
mkdir -p ~/.config/systemd/user
chmod 700 ~/.config/systemd/user

cat > ~/.config/systemd/user/auto-checkpoint-token << 'EOF'
PASTE_YOUR_TOKEN_HERE
EOF
chmod 600 ~/.config/systemd/user/auto-checkpoint-token

cat > ~/.config/systemd/user/dx-dispatch-token << 'EOF'
PASTE_YOUR_TOKEN_HERE
EOF
chmod 600 ~/.config/systemd/user/dx-dispatch-token
```

**Verification:**

```bash
# On each VM, verify token is readable
export OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.config/systemd/user/<service-account>-token)
op whoami
# Should show: "User Type: SERVICE ACCOUNT"
```

**Beads Update:**

```bash
bd update agent-skills-5f2.1 --status="completed"
```

---

### Task 5f2.2: Add Restart Rate Limiting (Systemd)

**Problem:** Services restart too aggressively on failure, causing API rate limits.

**Solution:** Add `StartLimitBurst=5`, `RestartSec=30`, exponential backoff.

**Per-VM Steps:**

```bash
# === All VMs ===

# 1. Find systemd user services using 1Password service accounts
systemctl --user list-units | grep -i "opencode\|dispatch\|checkpoint"

# 2. Edit each service file to add rate limiting
# Example: opencode-cleanup.service
sudo systemctl edit --user --full opencode-cleanup.service

# ADD these lines to [Service] section:
[Service]
# ... existing config ...
StartLimitIntervalSec=300
StartLimitBurst=5
RestartSec=30
Restart=on-failure

# 3. Reload systemd
systemctl --user daemon-reload

# 4. Verify with:
systemctl --user show opencode-cleanup.service | grep -E "StartLimit|RestartSec|Restart"
```

**Example Complete Service File:**

```ini
[Unit]
Description=OpenCode Session Cleanup
After=network.target

[Service]
Type=oneshot
ExecStart=/home/feng/agent-skills/slack-coordination/opencode-cleanup.sh
Environment=OP_SERVICE_ACCOUNT_TOKEN_FILE=%h/.config/systemd/user/opencode-cleanup-token
EnvironmentFile=-%h/.config/opencode.env

# Rate limiting (NEW)
StartLimitIntervalSec=300
StartLimitBurst=5
RestartSec=30
Restart=on-failure

[Install]
WantedBy=default.target
```

**Verification:**

```bash
# Test rate limiting by triggering failures
# Service should restart at most 5 times in 300 seconds
journalctl --user -u opencode-cleanup.service -n 50
```

**Beads Update:**

```bash
bd update agent-skills-5f2.2 --status="completed"
```

---

### Task 5f2.4: Restart Services with New Config

**Steps:**

```bash
# === homedesktop-wsl ===
systemctl --user restart opencode-cleanup.service
systemctl --user status opencode-cleanup.service

# === macmini ===
systemctl --user restart auto-checkpoint.service  # If exists
systemctl --user status auto-checkpoint.service

# === epyc6 ===
systemctl --user restart dx-dispatch.service
systemctl --user status dx-dispatch.service
```

**Health Check:**

```bash
# On each VM, verify:
# 1. Service is running
systemctl --user is-active <service-name>

# 2. No errors in logs
journalctl --user -u <service-name> --since "5 minutes ago" | grep -i error

# 3. Token is being used
op service-account ratelimit
# Should show used/remaining quota
```

**Beads Update:**

```bash
bd update agent-skills-5f2.4 --status="completed"
bd close agent-skills-5f2
```

---

## Phase 2: Auto-Checkpoint Feature (P1)

**Epic:** `agent-skills-tis` - Auto-Checkpoint: Intelligent dirty repo commits before ru sync

**Prerequisites:** Phase 1 complete, ZAI_API_KEY available in 1Password

---

### Task tis.1: Create Tiered Secret Cache

**Security Model:** Tier 2 secrets (read-only, low-risk) can be cached locally.

**Steps (per VM):**

```bash
# 1. Create secure cache directory
mkdir -p ~/.config/secret-cache
chmod 700 ~/.config/secret-cache

# 2. Create secrets.env with proper header
cat > ~/.config/secret-cache/secrets.env << 'EOF'
# ~/.config/secret-cache/secrets.env
# SECURITY: Tier 2 secrets only (read-only, low-risk)
# NEVER ADD: Database credentials, write-access tokens, PII-accessing tokens
# Created: $(date +%Y-%m-%d)
# Rotation: 30 days

ZAI_API_KEY=REPLACE_WITH_ACTUAL_KEY_FROM_1PASSWORD
# To get the key, run: op read "op://dev/Zhipu-Config/ZAI_API_KEY"
EOF

# 3. Set restrictive permissions
chmod 600 ~/.config/secret-cache/secrets.env

# 4. Add to global .gitignore (if not already)
echo "~/.config/secret-cache/" >> ~/.gitignore
```

**Verification:**

```bash
# Test sourcing
source ~/.config/secret-cache/secrets.env
echo "Key present: $([ -n "$ZAI_API_KEY" ] && echo "YES (${ZAI_API_KEY:0:10}...)" || echo "NO")"
# Should show: Key present: YES (78af149073...)

# Verify permissions
ls -la ~/.config/secret-cache/
# Should show: -rw------- (600)
```

**Beads Update:**

```bash
bd update agent-skills-tis.1 --status="completed"
```

---

### Task tis.2: Implement auto-checkpoint.sh (Pure Bash)

**Create main script:**

```bash
# ~/.local/bin/auto-checkpoint.sh
cat > ~/.local/bin/auto-checkpoint.sh << 'SCRIPT_EOF'
#!/bin/bash
# auto-checkpoint.sh - Commit dirty repos before ru sync
# Exit codes: 0=success, 1=clean, 2=error

set -euo pipefail

REPO_PATH="${1:-$(pwd)}"
LOG_PREFIX="[auto-checkpoint]"
LOG_FILE="${HOME}/logs/auto-checkpoint.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "$LOG_PREFIX $(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }
log_error() { echo "$LOG_PREFIX $(date '+%H:%M:%S') ERROR: $*" >&2 | tee -a "$LOG_FILE"; }

# Validate repo
cd "$REPO_PATH" || { log_error "Cannot cd to $REPO_PATH"; exit 2; }
[[ -d .git ]] || { log_error "Not a git repo: $REPO_PATH"; exit 2; }

# Check if dirty
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    log "Repo clean: $REPO_PATH"
    exit 0
fi

log "Dirty repo detected: $REPO_PATH"

# Beads sync (if .beads exists)
if [[ -d .beads ]]; then
    log "Running bd sync..."
    if ! bd sync 2>/dev/null; then
        log "WARNING: bd sync failed, proceeding with checkpoint"
    fi
fi

# Generate commit message
DIFF_STAT=$(git diff --stat HEAD 2>/dev/null | tail -1 || echo "changes")
COMMIT_MSG="[AUTO] checkpoint: $DIFF_STAT"

# Try GLM-4.5 for intelligent message (optional)
if [[ -f ~/.config/secret-cache/secrets.env ]]; then
    source ~/.config/secret-cache/secrets.env
    if [[ -n "${ZAI_API_KEY:-}" ]]; then
        if SMART_MSG=$(~/.local/bin/generate-commit-msg.sh "$DIFF_STAT" 2>/dev/null); then
            [[ -n "$SMART_MSG" ]] && COMMIT_MSG="$SMART_MSG"
        fi
    fi
fi

# Stage all changes
git add -A

# Commit
log "Committing: $COMMIT_MSG"
if ! git commit -m "$COMMIT_MSG"; then
    log_error "git commit failed"
    exit 2
fi

# Push
log "Pushing to remote..."
if ! git push 2>/dev/null; then
    log_error "git push failed (may need manual resolution)"
    exit 2
fi

log "Checkpoint complete: $COMMIT_MSG"
exit 0
SCRIPT_EOF

chmod +x ~/.local/bin/auto-checkpoint.sh
```

**Verification:**

```bash
# Test on dirty repo
cd ~/agent-skills
echo "# test" >> README.md
~/.local/bin/auto-checkpoint.sh ~/agent-skills

# Verify commit created
git log -1 --oneline
# Should show: [AUTO] checkpoint...

# Clean up
git checkout README.md
```

**Beads Update:**

```bash
bd update agent-skills-tis.2 --status="completed"
```

---

### Task tis.3: Add GLM Integration (Optional Enhancement)

**Create GLM helper script:**

```bash
# ~/.local/bin/generate-commit-msg.sh
cat > ~/.local/bin/generate-commit-msg.sh << 'GLM_EOF'
#!/bin/bash
# generate-commit-msg.sh - GLM-4.5 commit message generation
# Usage: generate-commit-msg.sh "diff stat summary"
# Returns: Commit message or empty string on failure

set -euo pipefail

DIFF_STAT="${1:-changes}"
TIMEOUT=5

# Source API key
[[ -f ~/.config/secret-cache/secrets.env ]] && source ~/.config/secret-cache/secrets.env
[[ -z "${ZAI_API_KEY:-}" ]] && exit 1

# Build prompt (simple, no thinking for speed)
PROMPT="Write a git commit message.

Changes: $DIFF_STAT

Rules:
- Start with [AUTO]
- Max 72 characters
- Use imperative mood
- No explanation

Message:"

# Call GLM-4.5 FLASH via Anthropic-compatible endpoint
# Note: claude-3-5-haiku-20241022 maps to GLM-4.5 Flash on z.ai
# Critical: thinking mode must be disabled for GLM compatibility
RESPONSE=$(curl -s --max-time "$TIMEOUT" \
    -X POST "https://api.z.ai/api/anthropic/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ZAI_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d "{
        \"model\": \"claude-3-5-haiku-20241022\",
        \"max_tokens\": 60,
        \"messages\": [{\"role\": \"user\", \"content\": $(echo "$PROMPT" | jq -Rs .)}],
        \"thinking\": {\"type\": \"disabled\"}
    }" 2>/dev/null || echo "")

# Extract message (Anthropic format)
MSG=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null || echo "")

# Validate and return
if [[ -n "$MSG" && "$MSG" == \[AUTO\]* && ${#MSG} -le 72 ]]; then
    echo "$MSG"
else
    exit 1
fi
GLM_EOF

chmod +x ~/.local/bin/generate-commit-msg.sh
```

**Verification:**

```bash
# Test GLM integration
~/.local/bin/generate-commit-msg.sh "README.md | 1 +"
# Should return: [AUTO] update readme

# Test with real diff
cd ~/agent-skills
echo "# test" >> README.md
~/.local/bin/generate-commit-msg.sh "$(git diff --stat | tail -1)"
git checkout README.md
```

**Beads Update:**

```bash
bd update agent-skills-tis.3 --status="completed"
```

---

### Task tis.4: Deploy Cron Entries (All 3 VMs)

**Cron Configuration:**

```bash
# === homedesktop-wsl ===
crontab -e

# ADD these lines:
# === AUTO-CHECKPOINT (runs before ru sync) ===
# Every 4 hours - agent-skills only
0 */4 * * * ~/.local/bin/auto-checkpoint.sh ~/agent-skills >> ~/logs/auto-checkpoint.log 2>&1
# Daily 12:00 UTC - all repos (5 min before ru sync --all)
0 12 * * * for repo in ~/agent-skills ~/affordabot ~/prime-radiant-ai ~/llm-common; do ~/.local/bin/auto-checkpoint.sh "$repo"; done >> ~/logs/auto-checkpoint.log 2>&1

# === macmini ===
crontab -e

# ADD these lines (5 min offset):
# Every 4 hours - agent-skills only
5 */4 * * * ~/.local/bin/auto-checkpoint.sh ~/agent-skills >> ~/logs/auto-checkpoint.log 2>&1
# Daily 12:00 UTC - all repos
5 12 * * * for repo in ~/agent-skills ~/affordabot ~/prime-radiant-ai ~/llm-common; do ~/.local/bin/auto-checkpoint.sh "$repo"; done >> ~/logs/auto-checkpoint.log 2>&1

# === epyc6 ===
crontab -e

# ADD these lines (10 min offset):
# Every 4 hours - agent-skills only
10 */4 * * * ~/.local/bin/auto-checkpoint.sh ~/agent-skills >> ~/logs/auto-checkpoint.log 2>&1
# Daily 12:00 UTC - all repos
10 12 * * * for repo in ~/agent-skills ~/affordabot ~/prime-radiant-ai ~/llm-common; do ~/.local/bin/auto-checkpoint.sh "$repo"; done >> ~/logs/auto-checkpoint.log 2>&1
```

**Verification:**

```bash
# Verify cron entries
crontab -l | grep auto-checkpoint

# Verify logs directory
ls -la ~/logs/auto-checkpoint.log

# Wait for next cron run (or test manually)
~/.local/bin/auto-checkpoint.sh ~/agent-skills
tail -20 ~/logs/auto-checkpoint.log
```

**Beads Update:**

```bash
bd update agent-skills-tis.4 --status="completed"
```

---

### Task tis.5: Integration Testing

**Test Plan:**

```bash
# === Test 1: Dirty repo checkpoint ===
cd ~/agent-skills
echo "# test-$(date +%s)" >> README.md
~/.local/bin/auto-checkpoint.sh ~/agent-skills

# Verify commit
git log -1 --oneline | grep "\[AUTO\]"
git status  # Should show clean

# === Test 2: Clean repo handling ===
~/.local/bin/auto-checkpoint.sh ~/agent-skills
# Should exit with code 0, log "Repo clean"

# === Test 3: Beads integration ===
cd ~/agent-skills
echo "# test" >> .beads/issues.jsonl 2>/dev/null || echo "No .beads"
~/.local/bin/auto-checkpoint.sh ~/agent-skills
# Should run bd sync before commit

# === Test 4: GLM fallback ===
# Temporarily hide API key
mv ~/.config/secret-cache/secrets.env ~/.config/secret-cache/secrets.env.bak
~/.local/bin/auto-checkpoint.sh ~/agent-skills
# Should use static [AUTO] checkpoint
mv ~/.config/secret-cache/secrets.env.bak ~/.config/secret-cache/secrets.env

# === Test 5: Multi-repo checkpoint ===
~/.local/bin/auto-checkpoint.sh --all-repos 2>/dev/null || for repo in ~/agent-skills ~/affordabot ~/prime-radiant-ai ~/llm-common; do ~/.local/bin/auto-checkpoint.sh "$repo"; done
# Should checkpoint all dirty repos
```

**Health Check Commands:**

```bash
# Check checkpoint count (last 24h)
grep -c "Checkpoint complete" ~/logs/auto-checkpoint.log

# Check GLM usage
grep -c "Committing:" ~/logs/auto-checkpoint.log

# Check errors
grep -i "error" ~/logs/auto-checkpoint.log | wc -l

# Verify recent commits
git log --oneline --since="1 day ago" | grep "\[AUTO\]"
```

**Beads Update:**

```bash
bd update agent-skills-tis.5 --status="completed"
bd close agent-skills-tis
```

---

## Rollback Procedures

### Phase 1 Rollback (Infrastructure)

```bash
# If service accounts have issues:
# 1. Revert to old token (if still available)
# 2. Or recreate service account in 1Password

# If rate limiting causes issues:
systemctl --user edit <service-name>
# Remove StartLimitBurst, RestartSec lines
systemctl --user daemon-reload
systemctl --user restart <service-name>
```

### Phase 2 Rollback (Auto-Checkpoint)

```bash
# Disable auto-checkpoint cron
crontab -l | grep -v auto-checkpoint | crontab -

# Or comment out in crontab
crontab -e
# Comment lines containing auto-checkpoint

# Remove scripts (optional)
rm -f ~/.local/bin/auto-checkpoint.sh
rm -f ~/.local/bin/generate-commit-msg.sh
rm -f ~/.config/secret-cache/secrets.env
```

---

## Final Verification

**After both phases complete:**

```bash
# === Phase 1 Verification ===
# 1. Service accounts working
op service-account list

# 2. Services rate-limited
systemctl --user show <service-name> | grep StartLimitBurst

# 3. Services running
systemctl --user status <service-name>

# === Phase 2 Verification ===
# 1. Scripts installed
ls -la ~/.local/bin/auto-checkpoint.sh
ls -la ~/.local/bin/generate-commit-msg.sh

# 2. Secrets cached
ls -la ~/.config/secret-cache/secrets.env

# 3. Cron entries active
crontab -l | grep auto-checkpoint

# 4. Logs working
tail -20 ~/logs/auto-checkpoint.log

# 5. Git history has [AUTO] commits
git log --oneline --since="1 hour ago" | grep "\[AUTO\]"
```

---

## Summary

| Epic | Tasks | Status |
|------|-------|--------|
| agent-skills-5f2 | 5f2.1, 5f2.2, 5f2.4 | ✅ Complete (infrastructure fixed) |
| agent-skills-tis | tis.1, tis.2, tis.3, tis.4, tis.5 | ✅ Complete (auto-checkpoint deployed) |

**Total Time:** 2-3 hours (including verification)

**Key Deliverables:**
- ✅ 3 service accounts deployed (opencode-cleanup, auto-checkpoint, dx-dispatch)
- ✅ Restart rate limiting configured on all services
- ✅ Auto-checkpoint script (pure bash, no Python dependencies)
- ✅ GLM-4.5 integration with fallback to static messages
- ✅ Cron entries deployed on all 3 VMs (staggered schedule)
- ✅ Tiered secret cache with proper security model

---

**Post-Deployment Monitoring:**

Check logs daily for first week:
```bash
tail -50 ~/logs/auto-checkpoint.log
journalctl --user -u <service-name> --since "1 day ago"
```

---

**Document:** `docs/INFRA_AND_CHECKPOINT_DEV_PROMPT.md`
**Version:** 1.0
**Last Updated:** 2026-01-24
# ARCHIVE / HISTORICAL
#
# This file is a historical one-shot build prompt. It may contain outdated paths
# and scheduling details. For current usage, prefer:
# - docs/START_HERE.md
# - scripts/auto-checkpoint.sh
# - scripts/auto-checkpoint-install.sh
