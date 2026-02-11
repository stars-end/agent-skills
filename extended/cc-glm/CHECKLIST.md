# CC-GLM Handoff Checklist

Completion gate and handoff checklist for delegated PR batches. Use when reviewing work completed by cc-glm headless delegates before committing/pushing.

## Quick Reference

```bash
# Check a single completed job
~/agent-skills/extended/cc-glm/scripts/cc-glm-handoff.sh check \
  --beads bd-xxxx \
  --worktree /tmp/agents/bd-xxxx/repo-name

# Report on all completed jobs in a batch
~/agent-skills/extended/cc-glm/scripts/cc-glm-handoff.sh report \
  --worktree /tmp/agents

# Print the checklist (for reference)
~/agent-skills/extended/cc-glm/scripts/cc-glm-handoff.sh checklist

# Sample output (dry-run)
~/agent-skills/extended/cc-glm/scripts/cc-glm-handoff.sh sample
```

## The Four Gates

### Gate 1: Diff Review

**Status:** [ ] PASS  [ ] FAIL  [ ] SKIP

**Checks:**
- Changes present in worktree (`git diff --stat HEAD` shows files)
- Diff matches expected task scope
- No unexpected changes (dotfiles, configs, other repos)

**Commands:**
```bash
cd /tmp/agents/bd-xxxx/repo-name
git diff --stat HEAD
git diff HEAD
```

**Acceptance criteria:**
- At least one file changed
- Changes align with task description
- No canonical repo paths modified (~/agent-skills, ~/prime-radiant-ai, etc.)

### Gate 2: Validation

**Status:** [ ] PASS  [ ] FAIL  [ ] SKIP

**Checks:**
- Tests pass (if applicable)
- Lint/format checks pass
- Validation commands documented in job output

**Commands:**
```bash
# Extract validation commands from job output
~/agent-skills/extended/cc-glm/scripts/cc-glm-handoff.sh check --beads bd-xxxx --worktree /tmp/agents/bd-xxxx/repo-name

# Run validation manually (from job output)
cd /tmp/agents/bd-xxxx/repo-name
make test  # or npm test, pytest, etc.
ruff check  # or eslint, prettier, etc.
```

**Acceptance criteria:**
- Job output includes validation commands OR explicitly states "no validation needed"
- Commands run successfully (exit 0)
- No critical errors or warnings

### Gate 3: Beads Status

**Status:** [ ] PASS  [ ] FAIL  [ ] SKIP

**Checks:**
- Issue still open (not already closed)
- Metadata consistent (repo, worktree, agent match task)

**Commands:**
```bash
bd show bd-xxxx
cat /tmp/cc-glm-jobs/bd-xxxx.meta
```

**Acceptance criteria:**
- Beads status is NOT "closed"
- Metadata fields populated correctly
- Worktree path is correct (not canonical)

### Gate 4: Risk Assessment

**Status:** [ ] PASS  [ ] FAIL  [ ] SKIP

**Checks:**
- Risks documented in job output
- Risks acceptable for commit
- No security-sensitive changes without review

**Look for in job output:**
- `risks:` or `risk notes:` section
- `known gaps:` or `edge cases:` section
- Explicit `risks: none` declaration

**Acceptance criteria:**
- Either: risks listed with mitigation OR explicit "none"
- Low blast radius changes preferred
- No auth/crypto/permissions changes without explicit review

## Decision Gate

Based on the four gates above:

```
[ ] READY TO COMMIT
[ ] NEEDS REVISION
[ ] BLOCKED
```

**Ready if:** All required gates PASS
**Revise if:** Any gate FAILS (document reason in handoff notes)
**Blocked if:** Risk assessment shows unacceptable risk

## Parallel Batch Mode (2-4 Threads)

### 1. Launch Jobs in Parallel

```bash
mkdir -p /tmp/cc-glm-jobs

# Create prompt files for each job
for beads in bd-001 bd-002 bd-003; do
  cat > /tmp/cc-glm-jobs/$beads.prompt.txt <<EOF
Beads: $beads
Repo: agent-skills
Worktree: /tmp/agents/$beads/agent-skills
Agent: cc-glm

Hard constraints:
- Work ONLY in the worktree above
- Do NOT run git commit/push. Do NOT open PRs.

Task:
- [Specific task description]

Expected outputs:
- Patch diff (unified)
- Commands to validate
- Notes: risks and edge cases
EOF
done

# Launch all jobs detached
for beads in bd-001 bd-002 bd-003; do
  ~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh start \
    --beads $beads \
    --repo agent-skills \
    --worktree /tmp/agents/$beads/agent-skills \
    --prompt-file /tmp/cc-glm-jobs/$beads.prompt.txt
done
```

### 2. Monitor Periodically (Every 5 Min)

```bash
# Status table for all jobs
~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh status

# Or use watch for continuous monitoring
watch -n 300 '~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh status'
```

Status table columns:
- `bead`: Beads ID
- `pid`: Process ID
- `state`: running / exited / missing
- `elapsed`: Time since start
- `bytes`: Log file size
- `last_update`: Time of last log write
- `retries`: Restart count

### 3. When Jobs Complete, Run Report

```bash
~/agent-skills/extended/cc-glm/scripts/cc-glm-handoff.sh report \
  --worktree /tmp/agents
```

Report summary:
- Total jobs
- Running / Completed counts
- Ready for handoff count
- Gate status summary (D=diff, V=validation, R=risks)

### 4. Process Each Job Through Check

```bash
for beads in bd-001 bd-002 bd-003; do
  ~/agent-skills/extended/cc-glm/scripts/cc-glm-handoff.sh check \
    --beads $beads \
    --worktree /tmp/agents/$beads/agent-skills
done
```

### 5. Commit Accepted Work, Restart Failed

```bash
# For passed gates:
cd /tmp/agents/bd-001/agent-skills
git add <files>
git commit -m "feat: bd-001 task description" -m "Co-Authored-By: cc-glm <noreply@anthropic.com>"
git push
bd close bd-001 --reason "Completed"

# For failed gates:
# 1. Document issues in handoff notes
echo "Gate 2 failed: tests not passing" > /tmp/cc-glm-jobs/bd-002.handoff-notes.txt
# 2. Either fix manually OR restart job
~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh start \
  --beads bd-002 \
  --repo agent-skills \
  --worktree /tmp/agents/bd-002/agent-skills \
  --prompt-file /tmp/cc-glm-jobs/bd-002.prompt-refined.txt
```

## Coordinator Report Format

The `report` command emits a concise table:

```
bead           state     duration   gates     action
────────────────────────────────────────────────────
bd-001         exited    12m        DVR       check
bd-002         running   8m         -         -
bd-003         exited    15m        D         check
```

- `state`: running / exited / missing
- `duration`: approximate runtime ( Xm, Xh )
- `gates`: D=diff, V=validation, R=risks
- `action`: "check" for completed jobs

JSON format available with `--format json`:

```bash
~/agent-skills/extended/cc-glm/scripts/cc-glm-handoff.sh report \
  --worktree /tmp/agents \
  --format json
```

## Exit Codes

- `0`: All gates passed (ready for commit/push)
- `1`: One or more gates failed
- `2`: Job still running (not ready for handoff)
- `3`: Invalid arguments or environment

## Handoff Notes Pattern

For jobs needing revision, create handoff notes:

```bash
cat > /tmp/cc-glm-jobs/bd-xxxx.handoff-notes.txt <<EOF
Handoff Review: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Reviewer: <agent-id>

FAILED GATES:
- Gate 2: Validation - tests not passing

SPECIFIC ISSUES:
- Test foo_test.py failing on line 42
- Lint error: unused variable in bar.py

ACTION:
- Restart with refined prompt focusing on test fixes

Prompt refinement:
"Fix the failing test in foo_test.py and remove unused variable from bar.py.
Run 'pytest' before outputting results."
EOF
```

## Integration With DX Workflows

This handoff checklist integrates with existing DX skills:

- **cc-glm**: Headless delegation (produces jobs)
- **cc-glm-job**: Background job management (monitors jobs)
- **cc-glm-handoff**: Completion gate (validates jobs)
- **sync-feature-branch**: Commit with trailers (consumes validated work)
- **create-pull-request**: Open PR (after commit/push)

## Safety Checks

The handoff script enforces:

1. **Worktree verification**: Ensures work is not in canonical repos
2. **Change presence**: Verifies files were actually modified
3. **Risk documentation**: Requires explicit risk assessment
4. **Beads consistency**: Checks metadata matches task

## Example Session

```bash
# 1. Launch 3 parallel jobs
for id in 001 002 003; do
  cc-glm-job.sh start --beads bd-$id --repo agent-skills \
    --worktree /tmp/agents/bd-$id/agent-skills \
    --prompt-file /tmp/cc-glm-jobs/bd-$id.prompt.txt
done

# 2. Monitor (run every 5 minutes)
cc-glm-job.sh status

# 3. When all complete, get report
cc-glm-handoff.sh report --worktree /tmp/agents

# 4. Check each completed job
for id in 001 002 003; do
  cc-glm-handoff.sh check --beads bd-$id \
    --worktree /tmp/agents/bd-$id/agent-skills
done

# 5. Commit passed work
for id in 001 003; do  # assume 002 failed
  cd /tmp/agents/bd-$id/agent-skills
  git add -A
  git commit -m "feat: bd-$id completed" -m "Co-Authored-By: cc-glm <noreply@anthropic.com>"
  git push
  bd close bd-$id --reason "Completed"
done

# 6. Handle failed job (bd-002)
cc-glm-job.sh start --beads bd-002 --repo agent-skills \
  --worktree /tmp/agents/bd-002/agent-skills \
  --prompt-file /tmp/cc-glm-jobs/bd-002.prompt-v2.txt
```
