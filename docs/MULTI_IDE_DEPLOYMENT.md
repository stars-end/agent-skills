# Multi-IDE Deployment (Canonical Set)

Canonical IDEs (V4.2.1):
- antigravity
- claude-code
- codex-cli
- opencode

This doc is the single “getting started” for configuring the canonical IDE set across canonical machines.

## Slack MCP (recommended)

1) Install + configure Slack MCP for all canonical IDEs:

```bash
~/agent-skills/scripts/setup-slack-mcp.sh all
```

2) Provide Slack credentials via environment (do not store in dotfiles like `~/.zshenv`):

```bash
export SLACK_MCP_XOXP_TOKEN=$(op item get --vault dev Slack-MCP-Secrets --fields label=xoxp_token)
export SLACK_MCP_ADD_MESSAGE_TOOL=true
```

3) Verify Slack MCP is present:
- `mcp-doctor/check.sh` (warn-only)

## SSH Doctor (recommended)

Local checks:

```bash
~/agent-skills/ssh-key-doctor/check.sh --local-only
```

Remote reachability (optional):

```bash
DX_SSH_DOCTOR_REMOTE=1 ~/agent-skills/ssh-key-doctor/check.sh --remote-only
```
