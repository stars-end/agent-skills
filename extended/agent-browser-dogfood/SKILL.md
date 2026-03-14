---
name: agent-browser-dogfood
description: Systematically explore and QA a web application with agent-browser. Use when the user wants exploratory testing, dogfooding, bug hunting, manual QA, or a structured browser-based issue report with screenshots and reproduction notes.
tags: [browser, qa, dogfood, exploratory-testing, verification]
allowed-tools:
  - Bash(agent-browser:*)
  - Bash(npx agent-browser:*)
  - Bash(mkdir:*)
---

# agent-browser-dogfood

Use this skill for structured browser QA with `agent-browser`.

## Default Output Pattern

```bash
OUTPUT_DIR=/tmp/agent-browser-dogfood
mkdir -p "$OUTPUT_DIR/screenshots"
export AGENT_BROWSER_SESSION=dogfood-session
```

## Workflow

1. Open target URL
2. Authenticate if needed
3. Snapshot app structure
4. Explore top-level nav and core flows
5. Record issues immediately with screenshots and notes
6. Summarize findings with repro steps

## Minimal Loop

```bash
agent-browser open <target-url>
agent-browser wait 2000
agent-browser snapshot -i
agent-browser screenshot /tmp/agent-browser-dogfood/screenshots/initial.png
agent-browser console
agent-browser errors
```

## What To Look For

- broken navigation
- console errors
- loading dead-ends
- failed form submissions
- empty/error states
- visual regressions that block use
- missing confirmations or bad success/failure feedback
- confusing interaction flows

## Evidence Standard

For every real finding, capture:

1. page/flow where it occurs
2. exact repro steps
3. screenshot path
4. console or error evidence if relevant
5. expected vs actual behavior

Suggested format:

```markdown
### Finding: <title>
- URL: <page>
- Steps:
  1. ...
  2. ...
- Expected: ...
- Actual: ...
- Evidence: /tmp/agent-browser-dogfood/screenshots/<file>.png
```

## Guardrails

- Document issues as you find them; do not reconstruct from memory later
- Re-snapshot after each meaningful navigation step
- Prefer breadth first, then go deep where the app is broken
- Keep Playwright out of the loop unless the user asks for automated tests

## Upstream Docs

- https://agent-browser.dev/skills
- https://github.com/vercel-labs/agent-browser/blob/main/skills/dogfood/SKILL.md
