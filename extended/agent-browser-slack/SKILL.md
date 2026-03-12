---
name: agent-browser-slack
description: Interact with Slack workspaces using agent-browser. Use when a CLI agent needs to inspect unread channels, navigate Slack, search conversations, capture screenshots, or extract workspace information through the browser UI.
tags: [browser, slack, automation, verification, cli]
allowed-tools:
  - Bash(agent-browser:*)
  - Bash(open:*)
---

# agent-browser-slack

Use `agent-browser` for Slack browser automation when a CLI agent needs a clean manual Slack interface.

## Start

If Slack is already open in a browser session and exposed via CDP, connect to it. Otherwise open the web app.

```bash
agent-browser open https://app.slack.com
agent-browser wait --load networkidle
agent-browser snapshot -i
```

## Common Tasks

### Check unread messages

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
agent-browser snapshot -i
agent-browser click @e_search
agent-browser fill @e_search "keyword"
agent-browser press Enter
agent-browser wait --load networkidle
agent-browser screenshot /tmp/slack-search.png
```

### Open a channel

```bash
agent-browser snapshot -i
agent-browser click @e_channel
agent-browser wait --load networkidle
agent-browser screenshot /tmp/slack-channel.png
```

## Guardrails

- Slack refs shift often; snapshot frequently
- Prefer screenshots for evidence when reporting unread state or message context
- Use this for browser/manual inspection, not for Slack Web API or coordinator-service work

## Upstream Docs

- https://agent-browser.dev/skills
- https://github.com/vercel-labs/agent-browser/blob/main/skills/slack/SKILL.md
