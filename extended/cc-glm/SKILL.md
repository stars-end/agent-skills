---
name: cc-glm
description: |
  Use cc-glm for batched delegation with plan-first execution.
  Batch by outcome (not file). Primary: local headless (cc-glm-job.sh). Optional: Task tool or cross-VM (dx-dispatch).
  Trigger when user mentions cc-glm, delegation, parallel agents, or batch execution.
tags: [workflow, delegation, automation, claude-code, glm, parallel]
allowed-tools:
  - Bash
  - Task
---

# cc-glm: Plan-First Batched Dispatch (V8.3 + V3.2 Operator Experience)

## Core Principle

**Batch by outcome, not by file.** One agent per coherent change set.

## When To Use

- Multi-file changes that form a coherent unit
- Backlog of independent tasks across repos
- Documentation + code changes that reference each other

## When NOT To Use

- Security-sensitive changes (auth, crypto, secrets)
- Architectural decisions
- High blast-radius refactors
- Single-file typo fixes (do it yourself)

---

## Pattern: Plan → Batch → Execute → Push

### Step 1: Plan (Required for Large/Cross-Repo)

**Threshold for plan file:**
- 6+ files, OR
- Cross-repo changes, OR
- High-risk changes

**Plan file template** (`<topic>-plan.md`):

```markdown
# Plan: [Task Name]

## Overview
[What we're doing]

## Tasks

### T1: [Batch Name]
- **depends_on**: []
- **repo**: [repo-name]
- **location**:
  - path/to/file1
  - path/to/file2
- **description**: [what to do]
- **validation**: [how to verify]
- **status**: Not Started
- **log**: [empty - agent fills]
- **files edited**: [empty - agent fills]

### T2: [Another Batch]
- **depends_on**: [T1]
...
```

**Fast path for small work** (1-2 files, single purpose):

Put mini-plan in Beads notes instead of file:

```markdown
## bd-xxx: Task Name
### Approach
- File: path/to/file
- Change: [what]
### Acceptance
- [ ] File modified
- [ ] Validation passed
```

### Step 2: Batch by Outcome

| Files | Approach | Agents |
|-------|----------|--------|
| 1-2, single purpose | Single agent | 1 |
| 3-5, coherent change | Single agent per repo | 1-2 |
| 6+ OR cross-repo | Batched by outcome | 2-3 |

**Rule**: 1 agent per repo or coherent change set, NOT 1 agent per file.

### Step 3: Execute with cc-glm-job.sh (Primary)

**Local headless execution is the primary method:**

```bash
# Start a background job with PTY for reliable output capture
cc-glm-job.sh start \
  --beads bd-xxx \
  --prompt-file /tmp/prompts/task.prompt \
  --repo my-repo \
  --worktree /tmp/agents/bd-xxx/my-repo \
  --pty

# Check status of all jobs
cc-glm-job.sh status

# Check single job health (V3.0: progress-aware)
cc-glm-job.sh check --beads bd-xxx

# View detailed health state
cc-glm-job.sh health --beads bd-xxx

# View log tail with optional ANSI stripping
cc-glm-job.sh tail --beads bd-xxx --lines 50 --no-ansi

# Restart a stalled job
cc-glm-job.sh restart --beads bd-xxx --pty

# Stop a running job (records outcome)
cc-glm-job.sh stop --beads bd-xxx

# Run watchdog with observe-only mode (V3.0)
cc-glm-job.sh watchdog --beads bd-xxx --once --observe-only

# Run watchdog with no-auto-restart (V3.0)
cc-glm-job.sh watchdog --beads bd-xxx --no-auto-restart --once
```

**Job artifacts location (V3.0):**
```bash
/tmp/cc-glm-jobs/
├── bd-xxx.pid         # Process ID
├── bd-xxx.log         # Current output log
├── bd-xxx.log.1       # Rotated log (preserved on restart)
├── bd-xxx.log.2       # Older rotated log
├── bd-xxx.meta        # Metadata (repo, worktree, retries, etc.)
├── bd-xxx.outcome     # Final outcome (exit_code, completed_at, state)
└── bd-xxx.contract    # Runtime contract (auth_source, model, base_url)
```

**Model selection (glm-5 recommended for complex tasks):**
```bash
# Pin to glm-5 for better reasoning
CC_GLM_MODEL=glm-5 cc-glm-job.sh start --beads bd-xxx --prompt-file /tmp/p.prompt --pty

# Or export for session
export CC_GLM_MODEL=glm-5
cc-glm-job.sh start --beads bd-xxx --prompt-file /tmp/p.prompt --pty
```

### Step 4: Monitor (V3.0 - Progress-Aware)

**V3.0 health states:**

| State | Meaning | Action |
|-------|---------|--------|
| `healthy` | Process running with CPU activity | None |
| `starting` | Within grace window | Wait |
| `stalled` | No CPU progress for N minutes | Restart (if retries left) |
| `exited_ok` | Exited with code 0 | Review output |
| `exited_err` | Exited with non-zero code | Check logs |
| `blocked` | Max retries exhausted | Manual intervention |
| `missing` | No job metadata found | Investigate |

**Check signals:**
1. **Process progress**: `cc-glm-job.sh check --beads bd-xxx`
2. **Log growth**: `cc-glm-job.sh tail --beads bd-xxx`

**Restart policy**: 1 restart max, then escalate.

```bash
# Quick status check
cc-glm-job.sh status

# View health with outcomes
cc-glm-job.sh health
```

### Step 5: Review, Push, PR

After all agents complete:

1. Review commits in each worktree: `git log --oneline -5`
2. Push each batch: `git push -u origin feature-bd-xxx`
3. Create 1 PR per batch: `gh pr create --title "bd-xxx: [description]"`

---

## Alternative Dispatch Methods

### Option A: Task Tool (Optional - for Codex Runtime)

If Task tool is available and you prefer subagent dispatch:

```yaml
Task:
  description: "T1: [batch name]"
  prompt: |
    You are implementing task T1 from plan.md

    ## Context
    - Plan: /path/to/plan.md
    - Dependencies: None (T1 has no depends_on)

    ## Your Task
    - **repo**: [repo-name]
    - **location**:
      - file1
      - file2
    - **description**: [what to do]
    - **validation**: [how to verify]

    ## Instructions
    1. cd to worktree: cd /tmp/agents/[beads-id]/[repo]
    2. Read ALL files in location first
    3. Implement changes for all acceptance criteria
    4. Keep work atomic and committable
    5. Update plan file:
       - status: Not Started → Completed
       - log: [your work summary]
       - files edited: [list of files you changed]
    6. Commit your work:
       - git add [specific files only]
       - git commit -m "..." (include Feature-Key and Agent trailers)
    7. DO NOT PUSH - orchestrator will push
    8. Return summary

  run_in_background: true
  subagent_type: general-purpose
```

### Option B: Cross-VM Dispatch (dx-dispatch)

For work that must run on a different VM:

```bash
# Dispatch to remote VM via Tailscale SSH
dx-dispatch macmini "cd ~/repo && make test"

# Or use Tailscale directly
tailscale ssh fengning@macmini "command"
```

**Canonical VM Dispatch Targets:**

| VM | Use Case | Status |
|----|----------|--------|
| `macmini` | macOS builds, iOS development | Enabled |
| `homedesktop-wsl` | Primary Linux dev, DCG, CASS | Enabled |
| `epyc12` | Linux compute, alternative to epyc6 | **Default Linux** |
| `epyc6` | GPU work, ML training | **DISABLED** (see gate) |

**When to use dx-dispatch:**
- Build requires macOS-specific tools (macmini)
- Heavy compute workloads (epyc12 - NOT epyc6)
- Remote environment has required secrets/tools

**When NOT to use dx-dispatch:**
- Local execution works (default to cc-glm-job.sh)
- No cross-VM requirement specified

**EPYC6 Enablement Gate:**

EPYC6 is currently **disabled for dispatch** due to runtime/session issues.
- Use `epyc12` as the default Linux dispatch target
- See [EPYC6_ENABLEMENT_GATE.md](docs/EPYC6_ENABLEMENT_GATE.md) for preflight checks and enablement criteria
- Gate must be explicitly passed before epyc6 can be used

---

## Wave Execution

For tasks with dependencies:

| Wave | Tasks | When to Start |
|------|-------|---------------|
| 1 | All tasks with `depends_on: []` | Immediately |
| 2 | Tasks depending on Wave 1 | After Wave 1 commits |
| 3 | Tasks depending on Wave 2 | After Wave 2 commits |

**Launch all Wave 1 tasks in parallel**, wait for completion, then Wave 2.

---

## Agent Prompt Template

Use this for either Task tool or prompt files:

```markdown
You are implementing a batched task from a development plan.

## Context
- Plan: [plan-file.md]
- Your Task: T[N]: [Name]
- Dependencies: [list or "None - this task has no dependencies"]

## Your Task
- **repo**: [repo-name]
- **location**:
  - path/to/file1
  - path/to/file2
- **description**: [full description]
- **validation**: [how to verify]

## Instructions
1. cd to repo: cd /tmp/agents/[beads-id]/[repo]
2. Read ALL files in location list first
3. Implement changes for all acceptance criteria
4. Keep work atomic and committable
5. Update plan file:
   - status: In Progress → Completed
   - log: [your work summary]
   - files edited: [list of files you changed]
6. Commit your work:
   - git add [specific files only]
   - git commit with Feature-Key and Agent trailers
7. DO NOT PUSH - orchestrator will push
8. Return summary of:
   - Files modified/created
   - Changes made
   - How criteria are satisfied
   - Validation performed or deferred

## Important
- Work only on files in your location list
- Other agents may be working in parallel
- Update plan file before yielding
- Commit, don't push
```

---

## Fallback (No cc-glm-job.sh Available)

If `cc-glm-job.sh` is unavailable, use `cc-glm-headless.sh` first (handles Z.ai auth/routing):

```bash
# Prefer: cc-glm-headless.sh (handles Z.ai base URL + token)
~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh --prompt-file /tmp/prompts/task.prompt

# With model selection via env
CC_GLM_MODEL=glm-5 ~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh --prompt-file /tmp/p.prompt
```

If `cc-glm-headless.sh` is also unavailable, raw `claude` requires explicit Z.ai configuration:

```bash
# Raw claude requires explicit env vars for Z.ai routing
ANTHROPIC_AUTH_TOKEN="$ZAI_API_KEY" \
ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" \
claude --model glm-5 -p "YOUR PROMPT" --output-format text

# Manual background with log capture
nohup claude --model glm-5 -p "$(cat /tmp/prompts/task.prompt)" \
  --output-format text \
  > /tmp/cc-glm-jobs/bd-xxx.log 2>&1 &
echo $! > /tmp/cc-glm-jobs/bd-xxx.pid
```

**Note**: Raw `claude` does NOT read `CC_GLM_MODEL`. Use `--model glm-5` flag explicitly.

---

## Remote Host Environment Setup (V3.0)

For deterministic headless execution on remote hosts (CI, epyc servers, etc.), ensure auth is properly configured. **Parallel jobs require deterministic auth - the legacy zsh/cc-glm fallback path is disabled by default.**

### Auth Resolution Order (First Match Wins) - V3.0

| Priority | Environment Variable | Description | Exit Code |
|----------|---------------------|-------------|-----------|
| 1 | `CC_GLM_AUTH_TOKEN` | Direct token (highest priority) | - |
| 2 | `CC_GLM_TOKEN_FILE` | Path to file containing token (V3.0) | 11 if error |
| 3 | `ZAI_API_KEY` | Plain token OR `op://` reference | - |
| 4 | `CC_GLM_OP_URI` | Explicit `op://` reference | - |
| 5 | Default | `op://dev/Agent-Secrets-Production/ZAI_API_KEY` | 10 if fail |

### V3.0 New Auth Option: CC_GLM_TOKEN_FILE

For environments with mounted secrets (Kubernetes, Docker secrets, CI):

```bash
# Use a mounted secret file
export CC_GLM_TOKEN_FILE=/run/secrets/zai-api-key
cc-glm-job.sh start --beads bd-xxx --prompt-file /tmp/p.prompt

# Exit code 11 if file not found or unreadable
# Exit code 11 if file is empty
```

### Recommended Setup for Remote Hosts

**Option A: 1Password Service Account (Recommended)**

```bash
# One-time setup on each host
~/agent-skills/scripts/create-op-credential.sh

# Verify
op read "op://dev/Agent-Secrets-Production/ZAI_API_KEY"
```

The script auto-discovers `OP_SERVICE_ACCOUNT_TOKEN` from:
- `OP_SERVICE_ACCOUNT_TOKEN_FILE` (if explicitly set)
- Canonical epyc12 path: `/home/fengning/.config/systemd/user/op-epyc12-token`
- `$HOME/.config/systemd/user/op-$(hostname)-token`
- Legacy: `$HOME/.config/systemd/user/op-macmini-token`

**Option B: Direct Token (CI/Secrets Manager)**

```bash
# Set directly in CI or secrets manager
export CC_GLM_AUTH_TOKEN="your-api-token"

# Or via ZAI_API_KEY (supports both plain and op://)
export ZAI_API_KEY="your-api-token"
```

**Option C: Token File (Mounted Secrets)**

```bash
# For Kubernetes/Docker secrets
export CC_GLM_TOKEN_FILE=/run/secrets/zai-api-key
```

**Option D: Explicit op:// Reference**

```bash
# Custom vault/item path
export CC_GLM_OP_URI="op://my-vault/my-item/my-field"
```

### Parallel Job Safety

The headless script fails fast when auth cannot be resolved, preventing silent failures in parallel dispatch:

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 1 | General error (missing prompt, etc.) |
| 2 | Argument parsing error |
| 10 | Auth resolution failed |
| 11 | Token file error (not found/unreadable/empty) |

```bash
# This will fail with actionable error if auth not configured
cc-glm-headless.sh --prompt "task"

# Error output includes remediation steps
```

### Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `CC_GLM_AUTH_TOKEN` | - | Direct auth token (highest priority) |
| `CC_GLM_TOKEN_FILE` | - | Path to file containing token (V3.0) |
| `ZAI_API_KEY` | - | Token or op:// reference |
| `CC_GLM_OP_URI` | - | Explicit op:// reference |
| `CC_GLM_OP_VAULT` | `dev` | 1Password vault name |
| `CC_GLM_BASE_URL` | `https://api.z.ai/api/anthropic` | API endpoint |
| `CC_GLM_MODEL` | `glm-5` | Model name |
| `CC_GLM_TIMEOUT_MS` | `3000000` | API timeout (50 min) |
| `CC_GLM_ALLOW_FALLBACK` | `0` | Set to `1` for legacy zsh fallback |
| `CC_GLM_STRICT_AUTH` | `1` | Set to `0` to suppress strict errors |
| `CC_GLM_DEBUG` | `0` | Set to `1` for debug logging |

### Troubleshooting Auth Failures

**Symptom**: Exit code 10 with "AUTH TOKEN RESOLUTION FAILED"

```bash
# Check if OP token file exists
ls -la ~/.config/systemd/user/op-$(hostname)-token

# Test op CLI directly
op read "op://dev/Agent-Secrets-Production/ZAI_API_KEY"

# Enable debug logging
CC_GLM_DEBUG=1 cc-glm-headless.sh --prompt "test"
```

**Symptom**: Exit code 11 with "Token file not found"

```bash
# Check file exists and is readable
ls -la $CC_GLM_TOKEN_FILE

# Check file is not empty
cat $CC_GLM_TOKEN_FILE
```

**Symptom**: "op CLI not found"

```bash
# Install 1Password CLI
# macOS: brew install 1password-cli
# Linux: https://developer.1password.com/docs/cli/get-started/
```

**Emergency Bypass** (not recommended for parallel jobs):

```bash
# Allow legacy zsh/cc-glm fallback
CC_GLM_ALLOW_FALLBACK=1 cc-glm-headless.sh --prompt "task"
```

---

## V3.0 Reliability Features

### Progress-Aware Health Detection

The job runner uses **CPU time** as the primary progress signal, not just log growth:

- If CPU time increases → process is healthy (even if log is quiet)
- If CPU time stalls AND log is stale → process is stalled
- Grace window for zero-output during startup

### Log Rotation (No Truncation)

On restart, logs are preserved:

```bash
/tmp/cc-glm-jobs/
├── bd-xxx.log      # Current log
├── bd-xxx.log.1    # First restart's log
└── bd-xxx.log.2    # Second restart's log
```

### Outcome Persistence

When jobs complete, outcome is recorded:

```bash
# bd-xxx.outcome
beads=bd-xxx
exit_code=0
completed_at=2026-02-17T12:00:00Z
state=success
```

### Restart Contract Integrity

When `--preserve-contract` is used, restarts verify the environment matches:

```bash
# Abort restart if model or base URL changed
cc-glm-job.sh restart --beads bd-xxx --preserve-contract
```

### Operator Guardrails

**ANSI stripping for clean output (machine-parse-safe):**
```bash
cc-glm-job.sh status --no-ansi
cc-glm-job.sh tail --beads bd-xxx --no-ansi
cc-glm-job.sh health --no-ansi
```

**Enhanced log locality hints (V3.1):**
```bash
cc-glm-job.sh status
# hint: local logs on hostname at /tmp/cc-glm-jobs (empty)
# hint: if jobs were dispatched to remote VMs, check:
#   - macmini: tailscale ssh fengning@macmini 'cc-glm-job.sh status'
#   - epyc6:   tailscale ssh feng@epyc6 'cc-glm-job.sh status'
```

**Multi-log-dir ambiguity guardrails (V3.1):**
```bash
# When multiple log directories exist, status/health/watchdog warn:
cc-glm-job.sh status
# WARN: Multiple log directories detected. Using default: /tmp/cc-glm-jobs
# WARN: Alternative dirs found:
#   - /tmp/cc-glm-jobs-alt1
#   - /tmp/cc-glm-jobs-alt2
# WARN: Use --log-dir <path> to target a specific directory
```

**Watchdog modes (V3.2):**

The watchdog supports three modes for controlling restart behavior:

| Mode | Flag | Behavior |
|------|------|----------|
| `normal` | (default) | Restart stalled jobs up to `--max-retries`, then mark blocked |
| `observe-only` | `--observe-only` | Monitor jobs but never restart (logs only) |
| `no-auto-restart` | `--no-auto-restart` | Mark jobs as blocked instead of restarting |

```bash
# Normal mode (default): restart once, then block
cc-glm-job.sh watchdog --interval 60

# Observe-only: monitor but don't restart (for manual supervision)
cc-glm-job.sh watchdog --observe-only --interval 30

# No-auto-restart: block on first stall
cc-glm-job.sh watchdog --no-auto-restart --once

# Combined: observe-only + single iteration
cc-glm-job.sh watchdog --observe-only --once
```

**Per-bead override control (V3.2):**

Set `no-auto-restart` for individual beads without affecting others:

```bash
# Enable no-auto-restart for a specific bead
cc-glm-job.sh set-override --beads bd-xxx --no-auto-restart true

# Disable no-auto-restart (restore normal behavior)
cc-glm-job.sh set-override --beads bd-xxx --no-auto-restart false

# Check current override status
cc-glm-job.sh set-override --beads bd-xxx
# override for bd-xxx:
#   no_auto_restart=true
```

When `no-auto-restart=true` is set for a bead, the watchdog will mark it as blocked instead of restarting, regardless of global settings.

**Viewing override state (V3.2):**

Use `--show-overrides` to see override status in status/health output:

```bash
# Show override column in status
cc-glm-job.sh status --show-overrides
# bead           pid      state        elapsed   bytes     last_update      retry  override   outcome
# bd-xxx         12345    running      5m        1024      10s ago          0      no-restart -

# Show override column in health
cc-glm-job.sh health --show-overrides
# bead           pid      health      last_update      retry  override   outcome
# bd-xxx         12345    healthy     10s ago          0      no-restart -
# bd-yyy         12346    blocked     2h ago           1      blocked    failed:1
```

**Override values:**
- (empty): Normal operation
- `no-restart`: Per-bead no-auto-restart is enabled
- `blocked`: Job has been blocked by watchdog

**Operator workflow for manual supervision:**

1. Start jobs in batch
2. Enable observe-only mode for monitoring
3. For jobs needing manual review, set per-bead override:
   ```bash
   cc-glm-job.sh set-override --beads bd-xxx --no-auto-restart true
   ```
4. When ready to resume normal watchdog:
   ```bash
   cc-glm-job.sh set-override --beads bd-xxx --no-auto-restart false
   cc-glm-job.sh watchdog  # back to normal mode
   ```

---

## Known Issues

### dx-delegate Broken
- **Symptom**: "Error: missing wrapper: ~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh"
- **Workaround**: Use `cc-glm-job.sh` directly (primary method above)
- **Status**: Deprecation pending

### Feature-Key Format
- **Issue**: `bd-epic.subtask` format rejected for large changes (190+ LOC)
- **Workaround**: Pre-create Beads ID with `bd create`
- **Hook expects**: `bd-xyz` format

---

## Anti-Patterns

| Anti-Pattern | Why Bad | Instead |
|--------------|---------|---------|
| 1 agent per file | Overhead explosion (11 PRs → 3 PRs) | Batch by repo/outcome |
| No plan file for cross-repo | Coordination chaos | Always plan first |
| Push per agent | PR explosion | Push once per batch |
| Multiple restarts | Brittle execution | 1 restart max |
| Complex state tracking | Cognitive overload | 2 signals only |

---

## Success Metrics

After 2 weeks, measure:
- Median PRs per epic: target 1-2
- Median worktrees per epic: target 1
- Blocked delegation rate: target <10%
- Founder intervention count: target 0
