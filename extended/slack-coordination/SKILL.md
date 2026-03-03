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

`agent_coordination_send_message` from [`scripts/lib/dx-slack-alerts.sh`](/private/tmp/agents/bd-3o07/agent-skills/scripts/lib/dx-slack-alerts.sh)

Use OpenClaw only for reasoning/summarization steps. Do **not** send deterministic operational alerts by:

- `openclaw message send`

When you need OpenClaw in this repo, treat it as triage/analysis input, then route the final output through deterministic transport.

## Systemd (canonical for service mode)

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
