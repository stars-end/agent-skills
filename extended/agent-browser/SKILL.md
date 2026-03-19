---
name: agent-browser
description: Browser automation CLI for AI agents. Use when a CLI agent needs the standard manual browser interface for exploratory verification, navigation, form interaction, screenshots, auth-cookie setup, or app walkthroughs. This is the primary manual browser tool for CLI agents; keep Playwright focused on CI/E2E and assertion-heavy automation.
tags: [browser, automation, verification, cli, manual, qa]
allowed-tools:
  - Bash(agent-browser:*)
  - Bash(npx agent-browser:*)
---

# agent-browser

Use `agent-browser` as the default manual browser surface for CLI agents.

## Browser Tooling Contract

- `agent-browser` = primary manual verification tool for CLI agents
- `Playwright` = CI/E2E, assertions, reproducible automated browser tests, and narrow request-interception debugging when the manual path cannot isolate the issue
- `subbrowser` = antigravity-specific exception, not the cross-agent default
- browser MCP surfaces = optional specialist/debug tools, not the standard manual path

## Use This For

- exploratory/manual verification of web apps
- checking a UI flow without writing Playwright specs
- screenshots and annotated evidence
- filling forms, clicking buttons, navigating menus
- reading page state, console issues, and response behavior
- setting auth cookies for controlled QA flows

## Do Not Use This For

- CI/CD browser tests
- replacing Playwright coverage
- fleet-wide background browser services

## Core Workflow

```bash
agent-browser open https://example.com
agent-browser wait 1500
agent-browser snapshot -i
```

Then interact, re-snapshot after major DOM changes, and capture evidence:

```bash
agent-browser find placeholder "Email" fill "user@example.com"
agent-browser find placeholder "Password" fill "password123"
agent-browser find text "Continue" click
agent-browser wait 2000
agent-browser snapshot -i
agent-browser screenshot /tmp/agent-browser-login.png
```

## Selector Guidance

Prefer these in order:

1. `find placeholder ...`
2. `find label ...`
3. `find text ...`
4. stable CSS selectors or `data-testid`
5. `@e*` refs from `snapshot -i`

`@e*` refs are useful, but on some builds they are less reliable than text/placeholder selectors. Treat them as a convenience, not the only interaction path.

## Useful Commands

```bash
# navigation + inspection
agent-browser open <url>
agent-browser wait 1500
agent-browser snapshot -i
agent-browser get url
agent-browser get text body
agent-browser console
agent-browser errors
agent-browser screenshot /tmp/page.png

# interaction
agent-browser click <selector>
agent-browser fill <selector> "text"
agent-browser type <selector> "text"
agent-browser press Enter

# cookies / auth
agent-browser cookies set <name> <value> --url <url> --sameSite Lax --secure
agent-browser cookies clear
```

## Sessions and Auth

For multi-command runs, either pass `--session` every time or export `AGENT_BROWSER_SESSION`:

```bash
export AGENT_BROWSER_SESSION=my-app
agent-browser open https://app.example.com
agent-browser snapshot -i
```

For authenticated QA flows using a known cookie contract:

```bash
agent-browser cookies set x-test-user "$TOKEN" --url https://app.example.com --sameSite Lax --secure
agent-browser open https://app.example.com/protected
agent-browser wait 2000
agent-browser snapshot -i
```

## Guardrails

- Always snapshot before relying on `@e*` refs
- Re-snapshot after navigation, modal open/close, or major DOM changes
- Prefer `agent-browser` directly over `npx agent-browser`
- Store ad hoc screenshots under `/tmp` unless the task explicitly needs repo evidence
- If a flow needs assertions, interception, or regression protection, move it to Playwright instead of overloading manual verification

## Quick Verification

```bash
agent-browser --help
agent-browser open https://example.com
agent-browser wait 1500
agent-browser snapshot -i
agent-browser close
```

## Upstream Docs

- https://agent-browser.dev/
- https://agent-browser.dev/skills
- https://github.com/vercel-labs/agent-browser/blob/main/README.md
