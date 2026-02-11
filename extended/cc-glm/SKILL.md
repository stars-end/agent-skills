---
name: cc-glm
description: |
  Use cc-glm (Claude Code wrapper using GLM-4.7) in headless mode to outsource repetitive work.
  Prefer detached background orchestration for multi-task backlogs, with mandatory monitoring.
  Trigger when user mentions cc-glm, glm-4.7, "headless", or wants to delegate easy/medium tasks to a junior agent.
tags: [workflow, delegation, automation, claude-code, glm, wave, parallel]
allowed-tools:
  - Bash
---

# cc-glm (Headless)

## When To Use

- Default delegation mechanism for **mechanical work estimated < 1 hour**:
  - search/triage, small refactors, doc edits, script wiring, low-risk CI fixes, adding tests
- You want a headless sub-agent loop without opening an interactive TUI.
- You have a backlog with multiple independent tasks and need parallel background workers.

## Background-First Orchestration (Required For Backlogs)

When there are multiple independent delegated tasks, use detached background workers by default.

- Target the highest safe parallelism for the backlog.
- Start with `2` workers, then scale to `3-4` as soon as tasks are low-risk and monitoring remains reliable.
- Do not launch more workers than you can actively monitor.
- Never run fire-and-forget delegation.

### Dependency-Aware Wave Planning

For backlogs with dependencies, use wave planning to orchestrate execution:

- **Task Schema**: Each task has `id`, `repo`, `worktree`, `prompt_file`, and optional `depends_on` (list of task IDs).
- **Wave Dispatch**: Tasks are partitioned into waves where each wave contains tasks whose dependencies are satisfied by previous waves.
- **Max Parallelism**: Each wave runs up to `max_workers` (default: 4) tasks in parallel.
- **Deterministic**: Uses topological sort with cycle detection.

Use the wave planner helper:

Required files per task:

- PID: `/tmp/cc-glm-jobs/<beads-id>.pid`
- Log: `/tmp/cc-glm-jobs/<beads-id>.log`
- Meta: `/tmp/cc-glm-jobs/<beads-id>.meta`

### Task Manifest (TOML)

Define tasks in a TOML manifest:

```toml
# /tmp/cc-glm-jobs/backlog.toml

[[tasks]]
id = "bd-001"
repo = "agent-skills"
worktree = "/tmp/agents/bd-001/agent-skills"
prompt_file = "/tmp/cc-glm-jobs/bd-001.prompt.txt"
depends_on = []  # no dependencies

[[tasks]]
id = "bd-002"
repo = "agent-skills"
worktree = "/tmp/agents/bd-002/agent-skills"
prompt_file = "/tmp/cc-glm-jobs/bd-002.prompt.txt"
depends_on = ["bd-001"]  # waits for bd-001

[[tasks]]
id = "bd-003"
repo = "agent-skills"
worktree = "/tmp/agents/bd-003/agent-skills"
prompt_file = "/tmp/cc-glm-jobs/bd-003.prompt.txt"
depends_on = ["bd-001"]  # parallel with bd-002

[[tasks]]
id = "bd-004"
repo = "prime-radiant-ai"
worktree = "/tmp/agents/bd-004/prime-radiant-ai"
prompt_file = "/tmp/cc-glm-jobs/bd-004.prompt.txt"
depends_on = ["bd-002", "bd-003"]  # waits for both
```

### Wave Dispatch Commands

```bash
# 1. Generate wave plan from manifest
~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh plan \
  --manifest /tmp/cc-glm-jobs/backlog.toml \
  --max-workers 4

# 2. Show wave status (poll every 5 minutes)
~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh status \
  --manifest /tmp/cc-glm-jobs/backlog.toml

# 3. Run all waves sequentially (auto-stops on failures)
~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh run \
  --manifest /tmp/cc-glm-jobs/backlog.toml

# 4. Run a specific wave only
~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh run \
  --manifest /tmp/cc-glm-jobs/backlog.toml \
  --wave 0
```

### Wave Dispatch Algorithm

1. **Topological Sort**: Tasks are sorted by `depends_on` edges; cycles cause errors.
2. **Wave Partitioning**: Tasks are grouped into waves where each wave contains tasks whose dependencies are all in previous waves.
3. **Per-Wave Parallelism**: Within each wave, up to `max_workers` tasks run in parallel.
4. **Wave Completion**: A wave is complete when all its tasks exit (success or failure).
5. **Sequential Waves**: Next wave starts only after all tasks in current wave complete.
6. **Stop on Failure**: Execution stops if any wave has failed tasks (prevents cascading errors).

### Partial Rerun Semantics

When a task fails:

```bash
# Re-run just the failed task (clears failed state)
~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh rerun \
  --manifest /tmp/cc-glm-jobs/backlog.toml \
  --task bd-002

# Continue with remaining waves after fixing failures
~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh run \
  --manifest /tmp/cc-glm-jobs/backlog.toml
```

- Failed tasks are marked with `state=failed` in wave metadata.
- `rerun` clears the failed state and re-executes just that task.
- Dependent waves are not re-run unless their specific dependencies failed.

### Monitoring Loop (For Waves)

Required monitoring loop (poll every 5 minutes):

- Verify wave states: `cc-glm-wave.sh status --manifest <path>`
- Verify process liveness: `ps -p <pid>` for each running task.
- Verify log growth (bytes or last modified time).
- Capture a status table for each poll: `wave | state | running | completed | failed`.
- If alive but no log growth for 20+ minutes, restart once via `rerun`.
- If still stalled after one restart, escalate as blocked with concise evidence.

## Prompt Contract (For Junior/Mid Delegates)

Use a strict prompt contract so delegated output is reviewable and low-variance:

- `Beads`, `Repo`, `Worktree`, `Agent` header fields.
- Hard constraints:
  - Work only in the worktree.
  - Never commit/push/open PR.
  - Never print secrets/dotfiles.
- Explicit scope:
  - in-scope file paths and clear non-goals.
  - acceptance criteria in measurable terms.
- Required output format:
  - files changed
  - unified diff
  - validation commands run + pass/fail
  - risk notes and known gaps

This keeps tasks clear enough for junior/mid execution while preserving orchestrator control.

## Delegation Boundary (DX V8.1)

**Delegate (default) if < 1 hour and mechanical.**

Do **not** delegate (or delegate only after you tighten scope) when:
- security-sensitive changes (auth, crypto, secrets, permissions)
- architectural decisions / broad refactors
- ambiguous requirements or high blast-radius changes

The orchestrator (you) remains responsible for:
- reviewing diffs
- running/confirming validation
- committing/pushing with required trailers

## Important Constraints

- Work in worktrees, not canonical clones (`~/agent-skills`, `~/prime-radiant-ai`, `~/affordabot`, `~/llm-common`).
- Do not print or dump dotfiles/configs (they often contain tokens).
- The delegate must **not** run `git commit`, `git push`, or open PRs.

## Recommended Setup (Deterministic)

To avoid relying on shell init files, prefer exporting `CC_GLM_AUTH_TOKEN` (and optionally `CC_GLM_BASE_URL`, `CC_GLM_MODEL`).

When set, `cc-glm-headless.sh` will invoke `claude` directly with these env vars (no `zsh -ic` needed).

If you use 1Password, you can also set `ZAI_API_KEY` as an `op://...` reference (or set `CC_GLM_OP_URI`) and `cc-glm-headless.sh` will resolve it via `op read` at runtime.

**Max Workers**: Set `CC_GLM_MAX_WORKERS` to override the default max parallelism (default: 4). This applies to both wave planning and manual worker management.

## Preferred Entry Point (Recommended)

Use the DX wrapper so prompts are V8.1 compliant and logs are kept:

```bash
dx-delegate --beads bd-xxxx --repo repo-name --prompt-file /path/to/task.txt
```

Logs are written under: `/tmp/dx-delegate/<beads-id>/...`

## Detached Background Pattern (Without dx-delegate)

Use this when `dx-delegate` is unavailable:

```bash
mkdir -p /tmp/cc-glm-jobs
cat > /tmp/cc-glm-jobs/bd-xxxx.meta <<'EOF'
beads=bd-xxxx
repo=repo-name
worktree=/tmp/agents/bd-xxxx/repo-name
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
retries=0
EOF

nohup ~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh \
  --prompt-file /tmp/cc-glm-jobs/bd-xxxx.prompt.txt \
  > /tmp/cc-glm-jobs/bd-xxxx.log 2>&1 & echo $! > /tmp/cc-glm-jobs/bd-xxxx.pid
disown
```

Monitoring example:

```bash
pid="$(cat /tmp/cc-glm-jobs/bd-xxxx.pid)"
ps -p "$pid" -o pid,ppid,stat,etime,command
wc -c /tmp/cc-glm-jobs/bd-xxxx.log
tail -n 20 /tmp/cc-glm-jobs/bd-xxxx.log
```

### Managed Job Helper (Simple Backlogs Without Dependencies)

Use the included helper script to standardize start/status/check:

```bash
# Start detached worker
~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh start \
  --beads bd-xxxx \
  --repo repo-name \
  --worktree /tmp/agents/bd-xxxx/repo-name \
  --prompt-file /tmp/cc-glm-jobs/bd-xxxx.prompt.txt

# Status table for all jobs
~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh status

# Health check for one job (exit 2 if stalled)
~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh check \
  --beads bd-xxxx \
  --stall-minutes 20
```

### Status Output Format

The wave status table format:

```
wave       state          started      pending  running  completed  failed   elapsed
--------------------------------------------------------------------------------------------------------
pending    0              -            3        0        0          0        -
running    1              14:23:15     1        3        2          0        5m32s
completed  2              14:28:47     0        0        4          0        12m15s
```

- `wave`: Wave number
- `state`: pending | running | completed | failed
- `started`: Start time (HH:MM:SS)
- `pending/running/completed/failed`: Task counts
- `elapsed`: Time since started

Individual task status also shown via the job helper.

### Quick Examples

```bash
# Plan and run a backlog with dependencies
cat > /tmp/cc-glm-jobs/backlog.toml <<'EOF'
[[tasks]]
id = "bd-001"
repo = "agent-skills"
worktree = "/tmp/agents/bd-001/agent-skills"
prompt_file = "/tmp/cc-glm-jobs/bd-001.prompt.txt"
depends_on = []

[[tasks]]
id = "bd-002"
repo = "agent-skills"
worktree = "/tmp/agents/bd-002/agent-skills"
prompt_file = "/tmp/cc-glm-jobs/bd-002.prompt.txt"
depends_on = ["bd-001"]
EOF

# Generate plan
~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh plan \
  --manifest /tmp/cc-glm-jobs/backlog.toml

# Run waves (monitor every 5 minutes)
~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh run \
  --manifest /tmp/cc-glm-jobs/backlog.toml &
WATCH_PID=$!

while sleep 300; do
  ~/agent-skills/extended/cc-glm/scripts/cc-glm-wave.sh status \
    --manifest /tmp/cc-glm-jobs/backlog.toml
  ! ps -p $WATCH_PID >/dev/null 2>&1 && break
done
```

### Without Wave Planner

For simple backlogs without dependencies, use the job helper directly:

## Quick Start

`cc-glm` is typically a **zsh function**, not a binary. In headless/non-interactive contexts, invoke via:

```bash
zsh -ic 'cc-glm -p "YOUR PROMPT" --output-format text'
```

If you need reliable quoting (recommended), use the wrapper script:

```bash
~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh --prompt-file /path/to/prompt.txt
```

## DX-Compliant Prompt Template

Use this template for delegated work (copy/paste):

```text
Beads: bd-xxxx
Repo: repo-name
Worktree: /tmp/agents/bd-xxxx/repo-name
Agent: cc-glm

Hard constraints:
- Work ONLY in the worktree path above (never touch canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common}).
- Do NOT run git commit/push. Do NOT open PRs.
- Output a unified diff patch, plus validation commands, plus brief risk notes.

Task:
- (1-5 bullets of the exact change)

Expected outputs:
- Patch diff (unified)
- Commands to validate (lint/tests)
- Notes: any edge cases or follow-ups
```

## Fallback

If `cc-glm` is not available on the host, fall back to standard Claude Code headless mode:

```bash
claude -p "YOUR PROMPT" --output-format text
```

## Patterns That Work Well

```bash
# 1) Run a tight task in a worktree
zsh -ic 'cc-glm -p "cd /tmp/agents/bd-1234/agent-skills && rg -n \"TODO\" -S . | head" --output-format text'

# 2) Generate a patch plan (no edits)
zsh -ic 'cc-glm -p "Read docs/CANONICAL_TARGETS.md and propose a 5-step verification plan." --output-format text'
```
