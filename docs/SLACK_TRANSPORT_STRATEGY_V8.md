# Slack Transport Strategy (V8)

## Scope

This document defines how this repo sends Slack messages and where new agents should read source-of-truth guidance before editing alert paths.

## Canonical Rule

### 1) Deterministic transport (no LLM required)
Use `agent_coordination_send_message` for operational notifications that are
rule-based, structured, or required by scripts.

Examples in this repo include:
- `scripts/dx-heartbeat-cron.sh` (heartbeat anomaly post)
- `scripts/dx-audit-cron.sh`
- `scripts/dx-alerts-digest.sh`
- `scripts/canonical-evacuate-active.sh`
- `scripts/founder-briefing-cron.sh`
- `scripts/dx-job-wrapper.sh`

### 2) Reasoning/triage paths (LLM)
OpenClaw is retained only for summarization and interpretation tasks, **not** for
final deterministic Slack transport.

Example:
- `scripts/dx-heartbeat-cron.sh` uses `openclaw agent` to read and summarize
  `~/.dx-state/HEARTBEAT.md`, then posts final output through
  `agent_coordination_send_message`.

## Why this split exists
- Deterministic Slack transport should be stable and auditable.
- LLM calls are non-deterministic and should stay isolated from the final
  delivery mechanism.

## Token and secret source of truth

Use 1Password item:
- `Agent-Secrets-Production` in `dev`

Canonical fields:
- `SLACK_BOT_TOKEN` (preferred in this repo’s transport layer)
- `SLACK_APP_TOKEN` (fallback)
- `ZAI_API_KEY`, `RAILWAY_API_TOKEN`, `GITHUB_TOKEN`

Load env with service account in non-interactive contexts:
```bash
~/agent-skills/scripts/dx-op-auth-status.sh --json
source ~/agent-skills/scripts/lib/dx-auth.sh
export RAILWAY_API_TOKEN="$(DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached 'op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN' 'railway_api_token')"
```

Read Slack tokens directly when needed for verification:
```bash
source ~/agent-skills/scripts/lib/dx-auth.sh
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached 'op://dev/Agent-Secrets-Production/SLACK_BOT_TOKEN' 'slack_bot_token'
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached 'op://dev/Agent-Secrets-Production/SLACK_APP_TOKEN' 'slack_app_token'
```

Implementation is resolved in:
- [`scripts/lib/dx-slack-alerts.sh`](/private/tmp/agents/bd-3o07/agent-skills/scripts/lib/dx-slack-alerts.sh)

## OpenClaw onboarding and expectations

OpenClaw remains the reasoning engine where needed.

Required for successful operation:
- Binary path and runtime: repository scripts currently call
  `~/.local/bin/mise x node@22.21.1 -- openclaw` in cron wrappers.
- Workspace/config for the chosen agent (for example `--agent all-stars-end`).

When a script changes from LLM flow to deterministic flow, only the final send step
should be updated to `agent_coordination_send_message`.

## CI and review guardrails

Repo consistency enforces deterministic transport policy in
[`scripts/lint-repo-consistency.sh`](/private/tmp/agents/bd-3o07/agent-skills/scripts/lint-repo-consistency.sh):

- `openclaw message send` is forbidden in `scripts/` for deterministic transport.
- `agent_coordination_send_message` must be used for deterministic posts.

If uncertain for a new path:
1. If the output is a stable alert/integrity event, use deterministic transport.
2. If the output is interpretation/summarization, use OpenClaw only.
3. If mixed, split reasoning and transport into separate steps.
