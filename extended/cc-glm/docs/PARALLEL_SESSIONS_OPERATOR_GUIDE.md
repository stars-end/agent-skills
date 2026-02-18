# Parallel cc-glm Sessions: Operator Guide (4-6 Jobs on epyc12)

**Target:** Running 4-6 concurrent cc-glm sessions on epyc12 with monitoring and restart policy.

**Script Version:** cc-glm-job.sh V3.2

---

## 1. Launch Template

### 1.1 Prerequisites

```bash
# Ensure cc-glm scripts are on PATH
export PATH="$HOME/agent-skills/extended/cc-glm/scripts:$PATH"

# Verify 1Password CLI auth (for API keys)
op user get --me || op signin

# Create log directory
mkdir -p /tmp/cc-glm-jobs
```

### 1.2 Single Job Launch (PTY Mode Recommended)

```bash
# Launch a single job with PTY-backed output capture
cc-glm-job.sh start \
  --beads bd-xxxx \
  --prompt-file /tmp/prompts/bd-xxxx.prompt \
  --repo myrepo \
  --worktree /tmp/agents/bd-xxxx/myrepo \
  --pty
```

### 1.3 Batch Launch (4-6 Jobs)

Create a launch script for batch operations:

```bash
#!/bin/bash
# batch-launch.sh - Launch 4-6 cc-glm jobs in parallel

JOBS=(
  "bd-task1:/tmp/prompts/bd-task1.prompt:prime-radiant-ai"
  "bd-task2:/tmp/prompts/bd-task2.prompt:affordabot"
  "bd-task3:/tmp/prompts/bd-task3.prompt:llm-common"
  "bd-task4:/tmp/prompts/bd-task4.prompt:agent-skills"
  # Optional 5th and 6th jobs:
  # "bd-task5:/tmp/prompts/bd-task5.prompt:prime-radiant-ai"
  # "bd-task6:/tmp/prompts/bd-task6.prompt:affordabot"
)

for job in "${JOBS[@]}"; do
  IFS=':' read -r beads prompt repo <<< "$job"
  echo "Starting: $beads ($repo)"
  cc-glm-job.sh start \
    --beads "$beads" \
    --prompt-file "$prompt" \
    --repo "$repo" \
    --worktree "/tmp/agents/${beads}/${repo}" \
    --pty
  sleep 2  # Stagger launches by 2s to avoid API rate limits
done

echo "Batch launched. Check status with: cc-glm-job.sh status"
```

### 1.4 Prompt File Template

```markdown
You are implementing task [T-N] from [plan-file.md].

## Context
- Plan: /path/to/plan.md
- Dependencies: [list or "None"]

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
5. Commit your work:
   - git add [specific files only]
   - git commit with Feature-Key and Agent trailers
6. DO NOT PUSH - orchestrator will push
7. Return summary

## Constraints
- Work only on files in your location list
- Feature-Key: [beads-id] must be in commit message
```

---

## 2. Monitoring Cadence and Commands

### 2.1 Status Check (All Jobs)

```bash
# Quick status table
cc-glm-job.sh status

# With ANSI stripping (for logging/piping)
cc-glm-job.sh status --no-ansi

# Show override flags
cc-glm-job.sh status --show-overrides

# Output example:
# bead           pid      state        elapsed   bytes     last_update      retry  outcome
# bd-task1       12345    running      5m20s     1024      10s ago          0      -
# bd-task2       12346    running      3m15s     2048      5s ago           0      -
# bd-task3       12347    stalled      25m0s     0         25m ago          0      -
# bd-task4       -        exited       -         512       2m ago           0      success:0 (180s)
```

### 2.2 Health Check (Classification)

```bash
# Detailed health classification
cc-glm-job.sh health

# Output example (V3.2 states):
# bead           pid      health      last_update      retry  outcome
# bd-task1       12345    healthy     10s ago          0      -
# bd-task2       12346    healthy     5s ago           0      -
# bd-task3       12347    starting    25m ago          0      -
# bd-task4       -        exited_ok   2m ago           0      success:0 (180s)
# bd-task5       -        exited_err  1m ago           1      failed:1 (45s)
# bd-task6       -        blocked     -                1      -
```

### 2.3 Individual Job Check

```bash
# Check if specific job is healthy
# Exit codes: 0=healthy/starting/exited_ok, 2=stalled, 3=exited_err/blocked
cc-glm-job.sh check --beads bd-task1 --stall-minutes 20
```

### 2.4 Tail Job Logs

```bash
# View last N lines of job log
cc-glm-job.sh tail --beads bd-task1 --lines 50

# With ANSI stripping
cc-glm-job.sh tail --beads bd-task1 --lines 50 --no-ansi
```

### 2.5 Recommended Monitoring Cadence

| Interval | Action | Command |
|----------|--------|---------|
| Every 5 min | Quick status scan | `cc-glm-job.sh status` |
| Every 15 min | Health classification | `cc-glm-job.sh health` |
| On alert | Log inspection | `cc-glm-job.sh tail --beads bd-xxx` |

### 2.6 Automated Watchdog

For persistent monitoring with auto-restart:

```bash
# Normal mode: restart stalled jobs up to max-retries
cc-glm-job.sh watchdog \
  --stall-minutes 20 \
  --interval 300 \
  --max-retries 1

# Observe-only mode: monitor but never restart (for manual supervision)
cc-glm-job.sh watchdog \
  --stall-minutes 20 \
  --interval 300 \
  --observe-only

# Run as background daemon
nohup cc-glm-job.sh watchdog \
  --stall-minutes 20 \
  --interval 300 \
  --max-retries 1 \
  --pidfile /tmp/cc-glm-watchdog.pid \
  > /tmp/cc-glm-watchdog.log 2>&1 &
```

### 2.7 Per-Bead Override Control (V3.2)

Disable auto-restart for specific beads:

```bash
# Disable auto-restart for a specific bead
cc-glm-job.sh set-override --beads bd-task3 --no-auto-restart true

# Re-enable auto-restart
cc-glm-job.sh set-override --beads bd-task3 --no-auto-restart false

# View current override state
cc-glm-job.sh set-override --beads bd-task3
```

---

## 3. Restart Policy

### 3.1 Rule: 1 Restart Max, Then Escalate

| Retry Count | Action | Rationale |
|-------------|--------|-----------|
| 0 | Automatic restart | Transient issue (API blip, slow startup) |
| 1 | Manual intervention | Indicates deeper problem (bad prompt, env issue) |

### 3.2 Manual Restart

```bash
# Restart a specific job (preserves metadata, rotates logs)
cc-glm-job.sh restart --beads bd-task1 --pty

# With contract preservation (abort if env drift detected)
cc-glm-job.sh restart --beads bd-task1 --pty --preserve-contract
```

### 3.3 Watchdog Auto-Restart Behavior

When using `cc-glm-job.sh watchdog`:

1. Detects stalled job (no progress for `--stall-minutes`)
2. Checks retry count against `--max-retries` (default: 1)
3. If retries < max: restarts job, increments counter
4. If retries >= max: marks job as **BLOCKED**, requires manual intervention

### 3.4 V3.2 Watchdog Modes

| Mode | Flag | Behavior |
|------|------|----------|
| Normal | (default) | Restart stalled jobs up to max-retries, then block |
| Observe-only | `--observe-only` | Monitor only, never restart |
| No-auto-restart | `--no-auto-restart` | Disable restarts globally (mark blocked instead) |
| Per-bead | `set-override` | Disable restarts for specific beads |

---

## 4. Log Locality and ANSI Parsing

### 4.1 Log File Locations

All job artifacts are stored under `/tmp/cc-glm-jobs/`:

| File | Purpose |
|------|---------|
| `bd-xxx.pid` | Process ID |
| `bd-xxx.log` | Current output log |
| `bd-xxx.log.<n>` | Rotated logs (preserved on restart, V3.1+) |
| `bd-xxx.meta` | Job metadata (key=value format) |
| `bd-xxx.outcome` | Final outcome metadata |
| `bd-xxx.outcome.<n>` | Rotated outcomes (forensic history, V3.1+) |
| `bd-xxx.contract` | Runtime contract (auth_source, model, base_url) |

### 4.2 Viewing Logs

```bash
# Using the tail command (recommended)
cc-glm-job.sh tail --beads bd-xxx --lines 50

# Direct log access
tail -50 /tmp/cc-glm-jobs/bd-xxx.log
tail -f /tmp/cc-glm-jobs/bd-xxx.log

# View metadata
cat /tmp/cc-glm-jobs/bd-xxx.meta

# View outcome
cat /tmp/cc-glm-jobs/bd-xxx.outcome
```

### 4.3 ANSI Stripping

Logs may contain ANSI escape codes. Use `--no-ansi` flag:

```bash
# Strip ANSI via built-in flag
cc-glm-job.sh tail --beads bd-xxx --no-ansi

# Strip ANSI from status output
cc-glm-job.sh status --no-ansi

# Manual stripping
sed 's/\x1b\[[0-9;]*m//g' /tmp/cc-glm-jobs/bd-xxx.log | tail -50

# Or use less with raw mode
less -R /tmp/cc-glm-jobs/bd-xxx.log
```

### 4.4 Zero-Byte Log Detection

If a log file is empty but process is running:

```bash
# Check log size
wc -c /tmp/cc-glm-jobs/bd-xxx.log

# If zero and process alive, restart with --pty for reliable capture
cc-glm-job.sh restart --beads bd-xxx --pty
```

### 4.5 Remote Log Locality Hints

V3.2 provides hints when logs might be on remote VMs:

```bash
# Status shows locality hint
cc-glm-job.sh status
# Output includes:
# hint: logs on epyc12 at /tmp/cc-glm-jobs (4 job(s))

# If local is empty, suggests where to check
# hint: if jobs were dispatched to remote VMs, check:
#   - macmini: tailscale ssh fengning@macmini 'cc-glm-job.sh status'
#   - epyc6:   tailscale ssh feng@epyc6 'cc-glm-job.sh status'
```

---

## 5. Failure Triage Checklist

### 5.1 Job Not Starting

| Symptom | Check | Fix |
|---------|-------|-----|
| `prompt file not found` | `ls -la /path/to/prompt.txt` | Create prompt file |
| `headless wrapper not executable` | `which cc-glm-headless.sh` | Add scripts dir to PATH |
| Auth failure | `op user get --me` | Re-authenticate with 1Password |
| API key missing | `echo $ZAI_API_KEY` | Set env var or check op:// reference |

### 5.2 Job Immediately Exits

| Symptom | Check | Fix |
|---------|-------|-----|
| Zero-byte log, immediate exit | `cc-glm-job.sh check --beads bd-xxx` | Restart with `--pty` |
| Permission denied | `ls -la /tmp/agents/bd-xxx/repo` | Verify worktree exists |
| Bad prompt syntax | `cat /tmp/prompts/bd-xxx.prompt` | Fix prompt file |

### 5.3 Job Stalled (No Progress)

| Symptom | Check | Fix |
|---------|-------|-----|
| No log updates for 20+ min | `cc-glm-job.sh tail --beads bd-xxx` | Check last output |
| Process still alive | `ps -p $(cat /tmp/cc-glm-jobs/bd-xxx.pid)` | May be long-running API call |
| API timeout | Check network/API status | May need manual restart |
| CPU time not increasing | Check `last_cpu_time` in meta | Process may be hung |

### 5.4 Blocked Job (Max Retries Exhausted)

```bash
# View blocked status
cc-glm-job.sh health | grep blocked

# Read metadata for diagnosis
cat /tmp/cc-glm-jobs/bd-xxx.meta

# Check blocked_reason
# - "max_retries": auto-restart limit reached
# - "no_auto_restart": per-bead override set

# Common causes:
# 1. Bad prompt (fix prompt file)
# 2. Missing dependencies (install in worktree)
# 3. API rate limiting (wait and retry)
# 4. Environment issues (check auth, paths)

# After fixing, clear blocked flag and restart
sed -i '/^blocked=/d' /tmp/cc-glm-jobs/bd-xxx.meta
sed -i '/^blocked_at=/d' /tmp/cc-glm-jobs/bd-xxx.meta
sed -i '/^blocked_reason=/d' /tmp/cc-glm-jobs/bd-xxx.meta
cc-glm-job.sh restart --beads bd-xxx --pty
```

### 5.5 Exit Code Reference (V3.2)

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success / Healthy / Starting / Exited OK |
| 1 | General error / Missing |
| 2 | Job stalled |
| 3 | Job exited with error / Blocked |
| 10 | Auth resolution failed |
| 11 | Token file error |

---

## 6. Escalation Path

### 6.1 When to Escalate

Escalate to human operator when:

1. **Job blocked after 1 restart** - likely requires prompt/environment fix
2. **Multiple jobs failing simultaneously** - systemic issue (API, auth, network)
3. **Worktree corruption** - git state issues require manual resolution
4. **API rate limiting** - need to stagger launches or reduce concurrency

### 6.2 Escalation Actions

```bash
# 1. Collect diagnostics
cc-glm-job.sh status --no-ansi --show-overrides > /tmp/diagnostics-status.txt
cc-glm-job.sh health --no-ansi --show-overrides > /tmp/diagnostics-health.txt
for f in /tmp/cc-glm-jobs/*.meta; do
  echo "=== $f ===" >> /tmp/diagnostics-meta.txt
  cat "$f" >> /tmp/diagnostics-meta.txt
done

# 2. Stop all jobs (if systemic issue)
for pidf in /tmp/cc-glm-jobs/*.pid; do
  beads=$(basename "$pidf" .pid)
  cc-glm-job.sh stop --beads "$beads"
done

# 3. Notify human operator (Slack/email/etc.)
# Include: diagnostics files, active jobs count, error patterns
```

### 6.3 Recovery Checklist

After human fixes root cause:

1. [ ] Verify fix applies to all affected jobs
2. [ ] Clear `blocked` flags in meta files
3. [ ] Reset retry count if desired: `sed -i 's/^retries=.*/retries=0/' /tmp/cc-glm-jobs/bd-xxx.meta`
4. [ ] Restart jobs with `--pty` flag
5. [ ] Monitor for 5-10 minutes to confirm stability
6. [ ] Resume normal monitoring cadence

---

## 7. Quick Reference

### Commands Summary

```bash
# Launch
cc-glm-job.sh start --beads bd-xxx --prompt-file /path/to/prompt --pty

# Status
cc-glm-job.sh status
cc-glm-job.sh status --no-ansi --show-overrides
cc-glm-job.sh health
cc-glm-job.sh check --beads bd-xxx

# Logs
cc-glm-job.sh tail --beads bd-xxx --lines 50 --no-ansi

# Control
cc-glm-job.sh restart --beads bd-xxx --pty
cc-glm-job.sh stop --beads bd-xxx
cc-glm-job.sh set-override --beads bd-xxx --no-auto-restart true

# Monitoring
cc-glm-job.sh watchdog --stall-minutes 20 --interval 300 --max-retries 1
cc-glm-job.sh watchdog --observe-only  # Monitor only, no restart
```

### Key Files

| Path | Purpose |
|------|---------|
| `/tmp/cc-glm-jobs/bd-xxx.pid` | Process ID |
| `/tmp/cc-glm-jobs/bd-xxx.log` | Current output log |
| `/tmp/cc-glm-jobs/bd-xxx.log.<n>` | Rotated logs |
| `/tmp/cc-glm-jobs/bd-xxx.meta` | Job metadata |
| `/tmp/cc-glm-jobs/bd-xxx.outcome` | Final outcome |
| `/tmp/cc-glm-jobs/bd-xxx.contract` | Runtime contract |
| `~/agent-skills/extended/cc-glm/scripts/` | Script location |

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `ZAI_API_KEY` | API key (or op:// reference) | op://dev/Agent-Secrets-Production/ZAI_API_KEY |
| `CC_GLM_MODEL` | Model to use | glm-5 |
| `CC_GLM_BASE_URL` | API endpoint | https://api.z.ai/api/anthropic |
| `CC_GLM_TIMEOUT_MS` | API timeout | 3000000 |

---

## Appendix A: cc-glm-job.sh Commands (V3.2)

| Command | Description |
|---------|-------------|
| `start` | Launch a cc-glm job in background |
| `status` | Show status table of jobs |
| `check` | Check single job health (exit codes indicate state) |
| `health` | Show detailed health classification |
| `restart` | Restart a job (preserves metadata, rotates logs) |
| `stop` | Stop a running job and record outcome |
| `tail` | Show last N lines of job log |
| `set-override` | Set per-bead override flags |
| `watchdog` | Run monitoring loop with auto-restart |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--beads <id>` | Beads issue ID | (required for most commands) |
| `--prompt-file <path>` | Path to prompt file | (required for start) |
| `--repo <name>` | Repository name | (optional metadata) |
| `--worktree <path>` | Worktree path | (optional metadata) |
| `--log-dir <dir>` | Log directory | /tmp/cc-glm-jobs |
| `--pty` | Use PTY-backed execution | false |
| `--stall-minutes <n>` | Minutes before stall detection | 20 |
| `--interval <secs>` | Watchdog check interval | 60 |
| `--max-retries <n>` | Max auto-restarts | 1 |
| `--once` | Single watchdog iteration | false |
| `--observe-only` | Watchdog monitors but never restarts | false |
| `--no-auto-restart` | Disable auto-restart globally | false |
| `--preserve-contract` | Abort restart if env contract mismatch | false |
| `--lines <n>` | Lines for tail command | 20 |
| `--no-ansi` | Strip ANSI codes from output | false |
| `--show-overrides` | Show override flags in status/health | false |
| `--pidfile <path>` | Watchdog PID file | (none) |

### Health States (V3.2)

| State | Meaning |
|-------|---------|
| `healthy` | Process running with recent activity |
| `starting` | Process running but within grace window |
| `stalled` | Process alive but no progress for N minutes |
| `exited_ok` | Process exited with code 0 |
| `exited_err` | Process exited with non-zero code |
| `blocked` | Max retries exhausted OR no-auto-restart set |
| `missing` | No metadata found for job |
