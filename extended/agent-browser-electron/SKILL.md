---
name: agent-browser-electron
description: Automate Electron desktop apps through agent-browser using Chrome DevTools Protocol. Use when the user needs to interact with Slack desktop, VS Code, Discord, Notion, Figma, or another Electron app from a CLI agent.
tags: [browser, electron, desktop, cdp, automation]
allowed-tools:
  - Bash(agent-browser:*)
  - Bash(open:*)
  - Bash(ps:*)
---

# agent-browser-electron

Use `agent-browser` to drive Electron apps via CDP.

## Core Workflow

1. Quit or relaunch the Electron app with `--remote-debugging-port`
2. Connect `agent-browser` to that port
3. Snapshot interactive elements
4. Interact using `@e*` refs

## macOS Examples

```bash
open -a "Slack" --args --remote-debugging-port=9222
agent-browser connect 9222
agent-browser snapshot -i
```

```bash
open -a "Visual Studio Code" --args --remote-debugging-port=9223
agent-browser connect 9223
agent-browser snapshot -i
```

## Linux Examples

```bash
slack --remote-debugging-port=9222
agent-browser connect 9222

code --remote-debugging-port=9223
agent-browser connect 9223
```

## Useful Commands

```bash
agent-browser connect 9222
agent-browser tab
agent-browser tab 1
agent-browser snapshot -i
agent-browser click @e4
agent-browser screenshot /tmp/electron-app.png
```

## Guardrails

- The remote debugging port must be present at app launch time
- Re-snapshot after switching tabs or views
- Use unique ports if multiple Electron apps are open
- This is for manual/interactive CLI automation, not for fleet-wide service-mode browser control

## Upstream Docs

- https://agent-browser.dev/skills
- https://github.com/vercel-labs/agent-browser/blob/main/skills/electron/SKILL.md
