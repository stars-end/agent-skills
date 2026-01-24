# One-Shot Implementation Prompt: Auto-Checkpoint Feature

**For:** Full-Stack Developer
**Epic:** `agent-skills-tis`
**Estimated Effort:** 2-3 hours

---

## Context

You're implementing an auto-checkpoint system for a multi-VM development environment (3 VMs: epyc6, macmini, homedesktop-wsl). The system auto-commits dirty work before `ru sync` runs, preventing sync from skipping repos with uncommitted changes.

**Key Constraints:**
- Pure bash (no Python dependencies)
- Must work from cron (no interactive prompts, no op CLI)
- Security-conscious (fintech application)
- GLM-4.5 FLASH API available but flaky (graceful degradation required)

---

## Your Tasks

### Task 1: Create Secret Cache (`agent-skills-tis.1`)

**Location:** `~/.config/secret-cache/secrets.env`

**Implementation:**

```bash
# 1. Create directory with proper permissions
mkdir -p ~/.config/secret-cache
chmod 700 ~/.config/secret-cache

# 2. Get ZAI_API_KEY from 1Password (one-time, manual)
op read "op://dev/Zhipu-Config/ZAI_API_KEY"

# 3. Create secrets.env
cat > ~/.config/secret-cache/secrets.env << 'EOF'
# SECURITY: Only low-risk, read-only API keys (Tier 2)
# NEVER ADD: Database credentials, write-access tokens, PII-accessing tokens
# Rotation: 30 days
# Created: 2026-01-24

ZAI_API_KEY=<paste-key-here>
EOF

# 4. Set permissions
chmod 600 ~/.config/secret-cache/secrets.env

# 5. Add to global gitignore
echo "**/.config/secret-cache/" >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global
```

**Verification:**
```bash
ls -la ~/.config/secret-cache/secrets.env
# Should show: -rw------- (0600)
```

---

### Task 2: Implement `auto-checkpoint.sh` (`agent-skills-tis.2`)

**Location:** `~/.local/bin/auto-checkpoint.sh`

**Implementation:**

```bash
#!/bin/bash
# auto-checkpoint.sh - Commit dirty repos before ru sync
# Usage: auto-checkpoint.sh [repo-path]
# Exit codes: 0=success, 1=clean (no action), 2=error

set -euo pipefail

REPO_PATH="${1:-$(pwd)}"
LOG_PREFIX="[auto-checkpoint]"

log() { echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error() { echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >&2; }

# Validate repo
cd "$REPO_PATH" || { log_error "Cannot cd to $REPO_PATH"; exit 2; }
[[ -d .git ]] || { log_error "Not a git repo: $REPO_PATH"; exit 2; }

REPO_NAME=$(basename "$REPO_PATH")
log "Checking $REPO_NAME..."

# Check if dirty (staged, unstaged, or untracked)
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    log "$REPO_NAME is clean, no action needed"
    exit 0
fi

log "Dirty repo detected: $REPO_NAME"

# Beads sync (if .beads exists) - non-fatal
if [[ -d .beads ]]; then
    log "Running bd sync..."
    if bd sync 2>&1 | while read -r line; do log "  bd: $line"; done; then
        log "bd sync complete"
    else
        log "WARNING: bd sync failed, proceeding with checkpoint"
    fi
fi

# Get diff summary for commit message
DIFF_STAT=$(git diff --stat HEAD 2>/dev/null | tail -1 | sed 's/^ *//' || echo "uncommitted changes")
[[ -z "$DIFF_STAT" ]] && DIFF_STAT="uncommitted changes"

# Default commit message
COMMIT_MSG="[AUTO] checkpoint: $DIFF_STAT"

# Try GLM-4.5 for intelligent message (optional, non-fatal)
if [[ -f ~/.local/bin/generate-commit-msg.sh && -f ~/.config/secret-cache/secrets.env ]]; then
    log "Attempting GLM-4.5 commit message generation..."
    SMART_MSG=$(~/.local/bin/generate-commit-msg.sh "$DIFF_STAT" 2>/dev/null || echo "")
    if [[ -n "$SMART_MSG" ]]; then
        COMMIT_MSG="$SMART_MSG"
        log "Using GLM-generated message"
    else
        log "GLM failed, using fallback message"
    fi
fi

# Stage all changes
log "Staging changes..."
git add -A

# Commit
log "Committing: $COMMIT_MSG"
if ! git commit -m "$COMMIT_MSG" 2>&1 | while read -r line; do log "  git: $line"; done; then
    log_error "git commit failed"
    exit 2
fi

# Push (with retry)
log "Pushing to remote..."
if ! git push 2>&1 | while read -r line; do log "  git: $line"; done; then
    log "First push failed, trying with --force-with-lease..."
    if ! git push --force-with-lease 2>&1 | while read -r line; do log "  git: $line"; done; then
        log_error "git push failed (manual resolution required)"
        exit 2
    fi
fi

log "Checkpoint complete for $REPO_NAME"
exit 0
```

**Installation:**
```bash
chmod +x ~/.local/bin/auto-checkpoint.sh
mkdir -p ~/logs
```

**Manual Test:**
```bash
# Create dirty state
echo "# test" >> ~/agent-skills/README.md

# Run checkpoint
~/.local/bin/auto-checkpoint.sh ~/agent-skills

# Verify
git -C ~/agent-skills log -1 --oneline
git -C ~/agent-skills status
```

---

### Task 3: Implement `generate-commit-msg.sh` (`agent-skills-tis.3`)

**Location:** `~/.local/bin/generate-commit-msg.sh`

**Implementation:**

```bash
#!/bin/bash
# generate-commit-msg.sh - GLM-4.5 FLASH commit message generation
# Usage: generate-commit-msg.sh "diff stat summary"
# Returns: Commit message on stdout, or exits 1 on failure

set -euo pipefail

DIFF_STAT="${1:-changes}"
TIMEOUT=5

# Source API key
if [[ ! -f ~/.config/secret-cache/secrets.env ]]; then
    exit 1
fi
source ~/.config/secret-cache/secrets.env

if [[ -z "${ZAI_API_KEY:-}" ]]; then
    exit 1
fi

# Build prompt (compact for token efficiency)
read -r -d '' PROMPT << 'PROMPT_EOF' || true
Write a git commit message for these changes:

CHANGES_PLACEHOLDER

Rules:
- Start with [AUTO]
- Max 72 characters total
- Imperative mood (add, fix, update)
- No quotes, no explanation, just the message
PROMPT_EOF

PROMPT="${PROMPT/CHANGES_PLACEHOLDER/$DIFF_STAT}"

# Escape for JSON
PROMPT_JSON=$(printf '%s' "$PROMPT" | jq -Rs .)

# Call GLM-4.5 via z.ai Coding endpoint (OpenAI-compatible)
# Coding endpoint works with all 3 canonical models: glm-4.7, glm-4.6v, glm-4.5
# Critical: thinking mode must be disabled to get content instead of reasoning_content
RESPONSE=$(curl -s --max-time "$TIMEOUT" \
    -X POST "https://api.z.ai/api/coding/paas/v4/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ZAI_API_KEY" \
    -d "{
        \"model\": \"glm-4.5\",
        \"max_tokens\": 60,
        \"messages\": [{\"role\": \"user\", \"content\": $PROMPT_JSON}],
        \"thinking\": {\"type\": \"disabled\"}
    }" 2>/dev/null) || exit 1

# Extract message content (OpenAI format)
MSG=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null) || exit 1

# Validate response
if [[ -z "$MSG" ]]; then
    exit 1
fi

# Clean up (remove quotes, trim whitespace)
MSG=$(echo "$MSG" | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Ensure [AUTO] prefix
if [[ "$MSG" != \[AUTO\]* ]]; then
    MSG="[AUTO] $MSG"
fi

# Truncate to 72 chars
if [[ ${#MSG} -gt 72 ]]; then
    MSG="${MSG:0:69}..."
fi

echo "$MSG"
```

**Installation:**
```bash
chmod +x ~/.local/bin/generate-commit-msg.sh
```

**Test:**
```bash
~/.local/bin/generate-commit-msg.sh "README.md | 5 ++"
# Expected: [AUTO] update readme
```

---

### Task 4: Deploy Cron Entries (`agent-skills-tis.4`)

**Deploy on each VM with staggered timing:**

#### epyc6 (test first)
```bash
ssh fengning@epyc6 'crontab -l 2>/dev/null; echo "
# === AUTO-CHECKPOINT (runs 5 min before ru sync) ===
# Every 4 hours - agent-skills only
10 */4 * * * ~/.local/bin/auto-checkpoint.sh ~/agent-skills >> ~/logs/auto-checkpoint.log 2>&1

# Daily 12:10 UTC - all repos
10 12 * * * for repo in ~/agent-skills ~/affordabot ~/prime-radiant-ai ~/llm-common; do [[ -d \"\$repo\" ]] && ~/.local/bin/auto-checkpoint.sh \"\$repo\"; done >> ~/logs/auto-checkpoint.log 2>&1
"' | ssh fengning@epyc6 'crontab -'
```

#### macmini (after 24h monitoring on epyc6)
```bash
ssh fengning@macmini 'crontab -l 2>/dev/null; echo "
# === AUTO-CHECKPOINT ===
5 */4 * * * ~/.local/bin/auto-checkpoint.sh ~/agent-skills >> ~/logs/auto-checkpoint.log 2>&1
5 12 * * * for repo in ~/agent-skills ~/affordabot ~/prime-radiant-ai ~/llm-common; do [[ -d \"\$repo\" ]] && ~/.local/bin/auto-checkpoint.sh \"\$repo\"; done >> ~/logs/auto-checkpoint.log 2>&1
"' | ssh fengning@macmini 'crontab -'
```

#### homedesktop-wsl (after macmini verified)
```bash
ssh fengning@homedesktop-wsl 'crontab -l 2>/dev/null; echo "
# === AUTO-CHECKPOINT ===
0 */4 * * * ~/.local/bin/auto-checkpoint.sh ~/agent-skills >> ~/logs/auto-checkpoint.log 2>&1
0 12 * * * for repo in ~/agent-skills ~/affordabot ~/prime-radiant-ai ~/llm-common; do [[ -d \"\$repo\" ]] && ~/.local/bin/auto-checkpoint.sh \"\$repo\"; done >> ~/logs/auto-checkpoint.log 2>&1
"' | ssh fengning@homedesktop-wsl 'crontab -'
```

**Verify:**
```bash
ssh fengning@epyc6 'crontab -l | grep auto-checkpoint'
```

---

### Task 5: Integration Testing (`agent-skills-tis.5`)

**Test Script:**

```bash
#!/bin/bash
# test-auto-checkpoint.sh - Integration test for auto-checkpoint

set -e
VM="${1:-epyc6}"
TEST_REPO="agent-skills"

echo "=== Testing auto-checkpoint on $VM ==="

# 1. Create dirty state
echo "1. Creating dirty state..."
ssh "fengning@$VM" "echo '# test-$(date +%s)' >> ~/$TEST_REPO/README.md"

# 2. Verify dirty
echo "2. Verifying dirty state..."
DIRTY=$(ssh "fengning@$VM" "cd ~/$TEST_REPO && git status --porcelain | wc -l")
[[ "$DIRTY" -gt 0 ]] || { echo "FAIL: Repo not dirty"; exit 1; }
echo "   Dirty files: $DIRTY"

# 3. Run checkpoint
echo "3. Running auto-checkpoint..."
ssh "fengning@$VM" "~/.local/bin/auto-checkpoint.sh ~/$TEST_REPO"

# 4. Verify clean
echo "4. Verifying clean state..."
CLEAN=$(ssh "fengning@$VM" "cd ~/$TEST_REPO && git status --porcelain | wc -l")
[[ "$CLEAN" -eq 0 ]] || { echo "FAIL: Repo still dirty"; exit 1; }

# 5. Verify commit
echo "5. Verifying commit..."
COMMIT=$(ssh "fengning@$VM" "cd ~/$TEST_REPO && git log -1 --oneline")
echo "   Last commit: $COMMIT"
[[ "$COMMIT" == *"[AUTO]"* ]] || { echo "FAIL: Missing [AUTO] prefix"; exit 1; }

# 6. Verify pushed
echo "6. Verifying push..."
AHEAD=$(ssh "fengning@$VM" "cd ~/$TEST_REPO && git status | grep -c 'ahead' || echo 0")
[[ "$AHEAD" -eq 0 ]] || { echo "FAIL: Not pushed to remote"; exit 1; }

echo "=== ALL TESTS PASSED ==="
```

**Run:**
```bash
chmod +x test-auto-checkpoint.sh
./test-auto-checkpoint.sh epyc6
```

---

## Acceptance Criteria

- [ ] `auto-checkpoint.sh` handles clean repos gracefully (exit 0)
- [ ] `auto-checkpoint.sh` commits and pushes dirty repos
- [ ] `auto-checkpoint.sh` includes Beads sync before commit
- [ ] `generate-commit-msg.sh` returns within 5 seconds or fails gracefully
- [ ] Fallback to static `[AUTO] checkpoint` when GLM fails
- [ ] Cron entries installed on all 3 VMs with proper stagger
- [ ] Integration test passes on epyc6
- [ ] 24-hour log monitoring shows no errors

---

## Security Checklist

- [ ] `~/.config/secret-cache/secrets.env` has 0600 permissions
- [ ] `~/.config/secret-cache/` has 0700 permissions
- [ ] ZAI_API_KEY is the ONLY secret in the cache (Tier 2 only)
- [ ] Secret cache directory is in global gitignore
- [ ] No secrets logged to `~/logs/auto-checkpoint.log`

---

## Rollback

If issues arise:
```bash
# Remove cron entries
ssh fengning@epyc6 'crontab -l | grep -v auto-checkpoint | crontab -'
ssh fengning@macmini 'crontab -l | grep -v auto-checkpoint | crontab -'
ssh fengning@homedesktop-wsl 'crontab -l | grep -v auto-checkpoint | crontab -'
```

---

## Deliverables

1. `~/.local/bin/auto-checkpoint.sh` deployed on all 3 VMs
2. `~/.local/bin/generate-commit-msg.sh` deployed on all 3 VMs
3. `~/.config/secret-cache/secrets.env` created on all 3 VMs
4. Cron entries active on all 3 VMs
5. Integration test passing
6. Close Beads tasks as you complete them: `bd update agent-skills-tis.X --status closed`

---

## Questions?

If you encounter issues, check:
1. `~/logs/auto-checkpoint.log` for errors
2. `crontab -l` for cron syntax
3. `git -C ~/agent-skills status` for repo state

Do NOT modify the security model or add additional secrets to the cache without tech lead approval.
