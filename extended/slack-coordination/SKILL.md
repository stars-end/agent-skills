---
name: slack-coordination
description: |
  Optional coordinator stack: Slack-based coordination loops (inbox polling, post-merge followups, lightweight locking).
  Uses direct Slack Web API calls and/or the slack-coordinator systemd service. Does not require MCP.
tags: [slack, coordination, workflow, optional]
allowed-tools:
  - Bash(slack-coordination/check-inbox.sh:*)
  - Bash(slack-coordination/post-merge-check.sh:*)
  - Bash(slack-coordination/can-dispatch.sh:*)
  - Bash(systemctl:*)
  - Bash(journalctl:*)
  - Read
---

# slack-coordination

This is an **optional** coordination layer. The 90% workflow does not depend on it.

## Slack transport boundary (V8)

For repository alert scripts, deterministic Slack delivery must use:

`agent_coordination_send_message` from `scripts/lib/dx-slack-alerts.sh`

Use OpenClaw only for reasoning/summarization steps. Do **not** send deterministic operational alerts by:

- `openclaw message send`

When you need OpenClaw in this repo, treat it as triage/analysis input, then route the final output through deterministic transport.

## Agent Coordination default destination

- Default operational follow-up destination resolves to `#fleet-events`.
- Canonical default channel ID is `C0A8YU9JW06`.
- In this workspace, literal channel names can fail (`channel_not_found`) even when transport is healthy.
- For deterministic follow-ups, use `agent_coordination_default_channel` (or explicit `C0A8YU9JW06`) instead of guessing channel names.

## Readiness + test post (deterministic)

```bash
source scripts/lib/dx-slack-alerts.sh

if ! agent_coordination_transport_ready; then
  echo "transport_not_ready"
  exit 1
fi

channel="$(agent_coordination_default_channel)"
echo "resolved_channel=${channel}"  # expected dev/default: C0A8YU9JW06 (#fleet-events)

agent_coordination_send_message \
  "Agent Coordination test post: deterministic transport OK" \
  "${channel}"
```

## Cron-safe follow-up recipe (due-only + idempotent)

```bash
#!/usr/bin/env bash
set -euo pipefail

export DX_AUTH_CACHE_ONLY=1
source "${HOME}/agent-skills/scripts/lib/dx-slack-alerts.sh"

log_file="$HOME/logs/agent-coordination-followup.log"
state_file="$HOME/.cache/dx/agent-coordination/followup.sent"
due_utc="${DUE_UTC:?set DUE_UTC, e.g. 2026-05-06T09:00:00Z}"
mkdir -p "$(dirname "$log_file")" "$(dirname "$state_file")"

{
  now_epoch="$(date -u +%s)"
  due_epoch="$(date -u -d "$due_utc" +%s)"
  [[ "$now_epoch" -ge "$due_epoch" ]] || exit 0   # due-only
  [[ ! -f "$state_file" ]] || exit 0              # idempotent

  agent_coordination_transport_ready
  channel="$(agent_coordination_default_channel)"
  agent_coordination_send_message \
    "Scheduled follow-up: <context>" \
    "$channel"
  touch "$state_file"
} >>"$log_file" 2>&1
```

Notes:
- Keep this non-interactive and cache-only for automation (`DX_AUTH_CACHE_ONLY=1`).
- Do not use raw `op read`, `op item get`, `op item list`, or `op whoami` in follow-up jobs.
- If a literal channel name fails, retry with `agent_coordination_default_channel` or `C0A8YU9JW06`.

## Systemd (canonical for service mode)

If you run the coordinator as a background service, use the scoped-env systemd unit:

- `systemd/slack-coordinator.service`
- Env file: `~/.config/slack-coordinator/.env` (op:// references resolved via `op run --`)

Install/enable via `scripts/dx-hydrate.sh`, then:

```bash
systemctl --user start slack-coordinator
journalctl --user -u slack-coordinator -f
```

## Manual commands (CLI mode)

### Check inbox

```bash
~/agent-skills/slack-coordination/check-inbox.sh
```

### Post-merge completion loop

```bash
~/agent-skills/slack-coordination/post-merge-check.sh <TASK_ID> <PR_NUMBER>
```

### Resource locking (best-effort)

```bash
~/agent-skills/slack-coordination/can-dispatch.sh
```

## Configuration

Provide required tokens via one of:
- systemd + `op run --env-file=...` (recommended)
- exported env vars in an interactive shell (manual use only)

Minimum vars used by the scripts:
- `SLACK_MCP_XOXP_TOKEN` (or `SLACK_BOT_TOKEN` depending on script)
- `SLACK_BOT_TOKEN` (preferred default via Agent-Secrets-Production)
- `SLACK_APP_TOKEN` (fallback)
- `SLACK_CHANNEL`
- `HUMAN_SLACK_ID`
