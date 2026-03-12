---
name: agent-browser
description: Browser automation CLI for AI agents. Use when a CLI agent needs a clean manual browser interface for exploratory verification, navigation, form interaction, screenshots, data extraction, or app walkthroughs. This is the standard manual browser surface for CLI agents; keep Playwright focused on CI/E2E and test automation.
tags: [browser, automation, verification, cli, manual, qa]
allowed-tools:
  - Bash(agent-browser:*)
  - Bash(npx agent-browser:*)
---

# agent-browser

Use `agent-browser` as the default manual browser interface for CLI agents.

## Use This For

- exploratory/manual verification of web apps
- checking a UI flow without writing Playwright specs
- screenshots and annotated evidence
- filling forms, clicking buttons, navigating menus
- reading page state, console issues, and network behavior

## Do Not Use This For

- CI/CD browser tests
- Playwright spec generation unless the user explicitly asks
- replacing app E2E coverage

**Policy split:**
- `agent-browser` = manual CLI verification
- `Playwright` = CI/E2E/assertion-heavy automation
- browser MCP surfaces = optional/specialist, not the default manual interface

## Core Workflow

1. Open the page
2. Wait for load
3. Snapshot interactive elements
4. Interact using `@e*` refs
5. Re-snapshot after navigation or major DOM changes

```bash
agent-browser open https://example.com
agent-browser wait --load networkidle
agent-browser snapshot -i
```

Example interaction loop:

```bash
agent-browser snapshot -i
agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait --load networkidle
agent-browser snapshot -i
agent-browser screenshot /tmp/agent-browser-login.png
```

## Standard Commands

```bash
# navigation
agent-browser open <url>
agent-browser wait --load networkidle
agent-browser close

# inspection
agent-browser snapshot -i
agent-browser console
agent-browser errors
agent-browser screenshot /tmp/page.png

# interaction
agent-browser click @e1
agent-browser fill @e2 "text"
agent-browser type @e2 "text"
agent-browser select @e3 "Option"
agent-browser press Enter
```

## Sessions and Auth

Use persistent sessions for recurring app work:

```bash
agent-browser --session-name my-app open https://app.example.com/login
agent-browser --session-name my-app wait --load networkidle
```

For multi-command flows, either repeat the session flag on each command or export `AGENT_BROWSER_SESSION`:

```bash
export AGENT_BROWSER_SESSION=my-app
agent-browser open https://app.example.com/dashboard
agent-browser snapshot -i
```

Save/load state when needed:

```bash
agent-browser state save /tmp/my-app-state.json
agent-browser state load /tmp/my-app-state.json
```

## Guardrails

- Always call `snapshot -i` before using refs like `@e1`
- Re-snapshot after navigation, modal open/close, or major DOM changes
- Prefer `agent-browser` directly over `npx agent-browser`
- Store screenshots and ad hoc artifacts under `/tmp` unless the task requires repo evidence

## Quick Verification

```bash
agent-browser --help
agent-browser open https://example.com
agent-browser wait --load networkidle
agent-browser snapshot -i
agent-browser close
```

## Upstream Docs

- https://agent-browser.dev/
- https://agent-browser.dev/skills
- https://github.com/vercel-labs/agent-browser/blob/main/README.md
