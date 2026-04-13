# dx-loop Actionable Notification Contract

This document describes the operator-facing notification contract for `dx-loop`
wave orchestration. Operators (humans monitoring automated waves) receive
notifications only when action is required.

## Notification Philosophy

**Low-noise, high-signal**: Notifications are emitted only for actionable states
that require operator attention. Healthy execution, pending states, and unchanged
blockers are suppressed to preserve operator focus.

## When Notifications Are Emitted

| State | Emitted? | Rationale |
|-------|----------|-----------|
| `merge_ready` | ✅ Always | Ready for HITL merge approval |
| `kickoff_env_blocked` | ✅ First occurrence | Bootstrap/worktree/host gates failed |
| `run_blocked` | ✅ First occurrence | dx-runner execution blocked |
| `review_blocked` | ✅ First occurrence | Review verdict blocked implementation |
| `needs_decision` | ✅ Always | Requires human intervention |
| `waiting_on_dependency` | ❌ Never | Automatic - upstream work in progress |
| `deterministic_redispatch_needed` | ❌ Never | Automatic retry in progress |
| Healthy/pending states | ❌ Never | No action required |

## Notification Payload Structure

Every emitted notification includes these fields:

### Required Fields

```json
{
  "notification_type": "merge_ready|blocked|needs_decision",
  "blocker_code": "merge_ready|kickoff_env_blocked|run_blocked|review_blocked|needs_decision",
  "message": "Human-readable description",
  "beads_id": "bd-5w5o.37.3",
  "wave_id": "wave-2026-03-24T12:00:00Z",
  "timestamp": "2026-03-24T12:34:56Z",
  "provider": "opencode|cc-glm|gemini",
  "phase": "implement|review|merge",
  "next_action": "What the operator should do"
}
```

### PR Artifact Fields (merge_ready only)

```json
{
  "pr_url": "https://github.com/stars-end/agent-skills/pull/393",
  "pr_head_sha": "6ce38c01b1e50d380a7068d2d94d8666471c7b7c"
}
```

### Context Fields (optional)

```json
{
  "task_title": "Fix notification policy",
  "attempt": 3,
  "max_attempts": 3,
  "metadata": {}
}
```

## Blocker Taxonomy

| Code | Meaning | Next Action |
|------|---------|-------------|
| `merge_ready` | PR artifacts present, CI passing | Review and merge PR via GitHub UI |
| `kickoff_env_blocked` | Bootstrap/worktree/host gates failed | Fix bootstrap environment (worktree/host/Beads) |
| `run_blocked` | dx-runner execution blocked | Wait for capacity or switch provider |
| `review_blocked` | Reviewer verdict blocked | Address review findings and re-submit |
| `needs_decision` | Requires human decision | Manual intervention required - check logs |
| `waiting_on_dependency` | Upstream dependencies unmet | (No notification - automatic) |
| `deterministic_redispatch_needed` | Stalled/timeout | (No notification - automatic retry) |

## Unchanged Suppression

To reduce noise, `dx-loop` suppresses repeat notifications when the blocker
state has not changed since the last emission. The hash is computed from:

```
sha256(blocker_code + severity + message + beads_id)[:16]
```

**Example**: If `bd-abc1` reports `run_blocked` with the same message three
times in a row, only the first notification is emitted. A notification is
emitted again if:
- The blocker code changes
- The message changes
- The task transitions to a different state

## CLI Output Format

Notifications are rendered for terminal consumption:

```
[MERGE_READY] PR artifacts present and checks passing
  Task: Fix notification policy (bd-5w5o.37.3)
  Provider: opencode
  Phase: merge
  PR: https://github.com/stars-end/agent-skills/pull/393
  SHA: 6ce38c01b1e50d380a7068d2d94d8666471c7b7c
  Next: Review and merge PR via GitHub UI
```

```
[BLOCKED] Runner reason: opencode_rate_limited
  Task: Implement feature X (bd-abc1)
  Provider: opencode
  Phase: implement
  Attempt: 2/3
  Next: Wait for capacity or switch provider
```

```
[NEEDS_DECISION] All retries exhausted
  Task: Complex refactor (bd-xyz9)
  Provider: cc-glm
  Phase: implement
  Next: All retries exhausted - inspect logs and decide: retry, skip, or takeover
```

## JSON Payload for Automation

For machine consumption (e.g., Slack webhooks, monitoring systems), use
`to_operator_payload()`:

```json
{
  "notification_type": "merge_ready",
  "blocker_code": "merge_ready",
  "message": "PR artifacts present and checks passing",
  "beads_id": "bd-5w5o.37.3",
  "wave_id": "wave-2026-03-24T12:00:00Z",
  "timestamp": "2026-03-24T12:34:56Z",
  "provider": "opencode",
  "phase": "merge",
  "next_action": "Review and merge PR via GitHub UI",
  "pr_url": "https://github.com/stars-end/agent-skills/pull/393",
  "pr_head_sha": "6ce38c01b1e50d380a7068d2d94d8666471c7b7c",
  "task_title": "Fix notification policy",
  "operator_handoff": true
}
```

## Operator Response Protocol

### merge_ready

1. Open the PR URL in browser
2. Review CI checks are green
3. Review code changes
4. Merge via GitHub UI (squash merge preferred)
5. `dx-loop` will detect merge and advance to next wave

### blocked (kickoff_env_blocked)

1. Check worktree exists: `ls /tmp/agents/<beads-id>/<repo>`
2. Check Beads Dolt is running: `bdx dolt test --json`
3. Check auth: `op whoami && railway whoami`
4. Fix the environment issue
5. Re-trigger the wave: `dx-loop start --epic <epic-id>`

### blocked (run_blocked)

1. Wait 5-10 minutes for capacity
2. If persistent, switch provider: `dx-runner start --provider cc-glm ...`
3. Monitor: `dx-loop status --wave-id <id> --json`

### blocked (review_blocked)

1. Check review findings in wave outcome
2. Create follow-up task for findings
3. After fixes, reviewer will re-evaluate

### needs_decision

1. Open the wave logs: `/tmp/dx-loop/waves/<wave-id>/logs/`
2. Inspect the failure reason
3. Decide: retry, skip task, or take over manually
4. If retry: `dx-loop start --epic <epic-id> --force`

## Implementation Reference

- `scripts/lib/dx_loop/notifications.py` - Notification manager and payload
- `scripts/lib/dx_loop/blocker.py` - Blocker classification and suppression
- `scripts/lib/dx_loop/state_machine.py` - Loop state and blocker codes
- `tests/dx_loop/test_notifications.py` - Test coverage for notification policy

## Related

- [dx-loop SKILL.md](../../extended/dx-loop/SKILL.md) - Main dx-loop documentation
- [dx-runner Runbook](../dx-runner/README.md) - dx-runner operations
