---
name: agent-browser-dogfood
description: Systematically explore and QA a web application with agent-browser. Use when the user wants exploratory testing, dogfooding, bug hunting, manual QA, or a structured browser-based issue report with screenshots and reproduction notes.
tags: [browser, qa, dogfood, exploratory-testing, verification]
allowed-tools:
  - Bash(agent-browser:*)
  - Bash(npx agent-browser:*)
  - Bash(mkdir:*)
  - Bash(cp:*)
---

# agent-browser-dogfood

Use this skill for systematic browser QA with `agent-browser`.

## Default Output Pattern

Unless the user specifies otherwise, use:

```bash
OUTPUT_DIR=/tmp/agent-browser-dogfood
mkdir -p "$OUTPUT_DIR/screenshots"
```

## Workflow

1. Open target URL
2. Authenticate if needed
3. Snapshot app structure
4. Explore top-level nav and core flows
5. Record each issue immediately with evidence
6. Summarize findings with repro steps

For consistent multi-command runs, prefer a named session:

```bash
export AGENT_BROWSER_SESSION=dogfood-session
```

## Minimal Loop

```bash
agent-browser open <target-url>
agent-browser wait --load networkidle
agent-browser snapshot -i
agent-browser screenshot /tmp/agent-browser-dogfood/screenshots/initial.png
agent-browser errors
agent-browser console
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

Suggested finding format:

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

- Document issues as you find them; do not rely on memory at the end
- Re-snapshot after each meaningful navigation step
- Prefer breadth first, then go deeper into broken areas
- Keep Playwright out of the loop unless the user asks for automated tests

## Upstream Docs

- https://agent-browser.dev/skills
- https://github.com/vercel-labs/agent-browser/blob/main/skills/dogfood/SKILL.md
