---
name: agent-browser-slack
description: Interact with Slack workspaces using agent-browser. Use when a CLI agent needs to inspect unread channels, search Slack, navigate channels, or capture browser-based Slack evidence without relying on MCP or Slack API workflows.
tags: [browser, slack, automation, verification, cli]
allowed-tools:
  - Bash(agent-browser:*)
  - Bash(npx agent-browser:*)
---

# agent-browser-slack

Use `agent-browser` for browser-based Slack inspection when a CLI agent needs a clean manual Slack interface.

## Start

```bash
export AGENT_BROWSER_SESSION=slack-browser
agent-browser open https://app.slack.com
agent-browser wait 2500
agent-browser snapshot -i
```

## Common Tasks

### Check unread state

```bash
agent-browser snapshot -i
agent-browser screenshot /tmp/slack-unreads.png
```

Look for:

- unread badges
- Activity tab
- DMs tab
- expanded unread sections

### Search Slack

```bash
agent-browser find placeholder "Search" fill "keyword"
agent-browser press Enter
agent-browser wait 2000
agent-browser screenshot /tmp/slack-search.png
```

### Open a channel

```bash
agent-browser find text "#channel-name" click
agent-browser wait 1500
agent-browser screenshot /tmp/slack-channel.png
```

## Guardrails

- Slack UI refs shift often; snapshot frequently
- Prefer screenshots when reporting unread state or message context
- Use this for browser/manual inspection, not Slack Web API or coordinator-service work

## Upstream Docs

- https://agent-browser.dev/skills
- https://github.com/vercel-labs/agent-browser/blob/main/skills/slack/SKILL.md
