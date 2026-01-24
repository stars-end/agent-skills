# Auto-Checkpoint Implementation Plan (V2 - Simplified)

## Overview

Auto-checkpoint automatically commits dirty work before `ru sync` runs, preventing sync from skipping repos with uncommitted changes.

**Design Principles:**
- Pure bash (no Python dependencies)
- Graceful degradation (works without LLM)
- Security-conscious (tiered secret management)
- Idempotent (safe to run multiple times)

## Problem Statement

```bash
ru sync agent-skills
# → WARNING: Skipping agent-skills (uncommitted changes)
```

Agents working on repos block updates until work is manually committed.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CRON SCHEDULE (All VMs)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Every 4 hours (agent-skills):                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ VM               auto-checkpoint    ru sync              │  │
│  │ homedesktop-wsl  :00               :05                   │  │
│  │ macmini          :05               :10                   │  │
│  │ epyc6            :10               :15                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Daily 12:00 UTC (all repos):                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 12:00  auto-checkpoint.sh --all-repos                    │  │
│  │ 12:05  ru sync --all                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Secret Cache: `~/.config/secret-cache/secrets.env`

**Security Model:** Tiered secrets - only Tier 2 (read-only, low-risk) secrets cached.

```bash
# ~/.config/secret-cache/secrets.env
# SECURITY: Only low-risk, read-only API keys (Tier 2)
# NEVER ADD: Database credentials, write-access tokens, PII-accessing tokens
# Rotation: 30 days
# Created: YYYY-MM-DD

ZAI_API_KEY=xxx-your-glm-key-xxx
```

**Requirements:**
- File permissions: `chmod 600`
- Directory permissions: `chmod 700`
- Full disk encryption (LUKS) verified on VM
- Listed in `.gitignore`
- 30-day rotation policy

### 2. Core Script: `~/.local/bin/auto-checkpoint.sh`

**Pure bash, no Python dependencies.**

```bash
#!/bin/bash
# auto-checkpoint.sh - Commit dirty repos before ru sync
set -euo pipefail

REPO_PATH="${1:-$(pwd)}"
LOG_PREFIX="[auto-checkpoint]"

log() { echo "$LOG_PREFIX $(date '+%H:%M:%S') $*"; }
log_error() { echo "$LOG_PREFIX $(date '+%H:%M:%S') ERROR: $*" >&2; }

# Validate repo
cd "$REPO_PATH" || { log_error "Cannot cd to $REPO_PATH"; exit 2; }
[[ -d .git ]] || { log_error "Not a git repo: $REPO_PATH"; exit 2; }

# Check if dirty
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    log "Repo clean, no action needed"
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
        SMART_MSG=$(~/.local/bin/generate-commit-msg.sh "$DIFF_STAT" 2>/dev/null || echo "")
        [[ -n "$SMART_MSG" ]] && COMMIT_MSG="$SMART_MSG"
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

log "Checkpoint complete"
exit 0
```

### 3. LLM Integration: `~/.local/bin/generate-commit-msg.sh`

**Optional enhancement - curl-based, 5-second timeout.**

```bash
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

# Build prompt
PROMPT="Write a git commit message.

Changes: $DIFF_STAT

Rules:
- Start with [AUTO]
- Max 72 characters
- Use imperative mood
- No explanation

Message:"

# Call GLM-4.5 FLASH
RESPONSE=$(curl -s --max-time "$TIMEOUT" \
    -X POST "https://api.z.ai/api/paas/v4/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ZAI_API_KEY" \
    -d "{
        \"model\": \"glm-4-flash\",
        \"messages\": [{\"role\": \"user\", \"content\": $(echo "$PROMPT" | jq -Rs .)}],
        \"max_tokens\": 60,
        \"temperature\": 0.3
    }" 2>/dev/null || echo "")

# Extract message
MSG=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null || echo "")

# Validate and return
if [[ -n "$MSG" && "$MSG" == \[AUTO\]* && ${#MSG} -le 72 ]]; then
    echo "$MSG"
else
    exit 1
fi
```

### 4. Cron Configuration

**Per-VM crontab entries:**

```bash
# === AUTO-CHECKPOINT (runs before ru sync) ===

# Every 4 hours - agent-skills only
# Stagger: homedesktop-wsl :00, macmini :05, epyc6 :10
0 */4 * * * ~/.local/bin/auto-checkpoint.sh ~/agent-skills >> ~/logs/auto-checkpoint.log 2>&1

# Daily 12:00 UTC - all repos (5 min before ru sync --all)
0 12 * * * for repo in ~/agent-skills ~/affordabot ~/prime-radiant-ai ~/llm-common; do ~/.local/bin/auto-checkpoint.sh "$repo"; done >> ~/logs/auto-checkpoint.log 2>&1
```

**Adjust minute offset per VM:**
| VM | auto-checkpoint | ru sync |
|----|-----------------|---------|
| homedesktop-wsl | :00 | :05 |
| macmini | :05 | :10 |
| epyc6 | :10 | :15 |

## File Structure

```
~/.local/bin/
├── auto-checkpoint.sh          # Main checkpoint script
└── generate-commit-msg.sh      # Optional GLM integration

~/.config/secret-cache/
└── secrets.env                 # Tier 2 secrets (ZAI_API_KEY only)

~/logs/
└── auto-checkpoint.log         # Checkpoint logs

~/agent-skills/docs/
└── AUTO_CHECKPOINT_IMPLEMENTATION.md  # This file
```

## Security Model

### Tiered Secret Management

| Tier | Storage | Examples | Rationale |
|------|---------|----------|-----------|
| **Tier 1** | op run only | DB creds, write tokens, auth tokens | High blast radius |
| **Tier 2** | Cached file OK | ZAI_API_KEY (read-only AI API) | Low blast radius |

### Tier 2 Cache Requirements

- [ ] File permissions: 0600
- [ ] Directory permissions: 0700
- [ ] Full disk encryption (LUKS) verified
- [ ] Listed in global .gitignore
- [ ] 30-day rotation documented
- [ ] Never committed to any repo

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (checkpoint created or repo clean) |
| 1 | Repo was clean (no action needed) |
| 2 | Git operation failed |

## Failure Modes

| Failure | Handling | User Action |
|---------|----------|-------------|
| ZAI_API_KEY missing | Use static `[AUTO] checkpoint` | None |
| GLM API timeout | Use static `[AUTO] checkpoint` | None |
| Git push fails | Log error, exit 2 | Check network/auth |
| Beads sync fails | Log warning, proceed | Resolve manually |
| Repo clean | Exit 0 (success) | None |

## Testing Plan

### Phase 1: Manual Testing (epyc6)
```bash
# Create dirty state
echo "test" >> ~/agent-skills/README.md

# Run checkpoint
~/.local/bin/auto-checkpoint.sh ~/agent-skills

# Verify
git log -1 --oneline
git status
```

### Phase 2: Cron Testing (epyc6 only)
1. Add cron entry for epyc6
2. Monitor logs for 24 hours
3. Verify checkpoints and syncs work together

### Phase 3: Rollout
1. Deploy to homedesktop-wsl
2. Deploy to macmini
3. Monitor for 1 week

## Rollback

```bash
# Disable per-VM
crontab -l | grep -v auto-checkpoint | crontab -

# Or comment out in crontab
crontab -e
# Comment lines containing auto-checkpoint
```

## Monitoring

```bash
# Check checkpoint count (last 24h)
grep -c "Checkpoint complete" ~/logs/auto-checkpoint.log

# Check fallback usage
grep -c "static message" ~/logs/auto-checkpoint.log

# Check errors
grep -c "ERROR" ~/logs/auto-checkpoint.log
```

## Dependencies

- `git` - Version control
- `bd` - Beads CLI (optional, for .beads sync)
- `curl` - HTTP client (for GLM integration)
- `jq` - JSON parsing (for GLM integration)

**No Python required.**

## Beads Tracking

**Epic:** `agent-skills-tis` - Auto-Checkpoint: Intelligent dirty repo commits before ru sync

**Subtasks:**
1. `agent-skills-tis.1` - Create tiered secret cache with ZAI_API_KEY
2. `agent-skills-tis.2` - Implement auto-checkpoint.sh (pure bash)
3. `agent-skills-tis.3` - Add generate-commit-msg.sh with GLM-4.5
4. `agent-skills-tis.4` - Deploy cron entries on all 3 VMs
5. `agent-skills-tis.5` - Integration testing

---

**Version:** V2 (Simplified)
**Last Updated:** 2026-01-24
**Reviewed By:** Tech Lead
