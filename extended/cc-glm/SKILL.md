---
name: cc-glm
description: |
  Use cc-glm (Claude Code wrapper using GLM-4.7) in headless mode to outsource repetitive work.
  Trigger when user mentions cc-glm, glm-4.7, "headless", or wants to delegate easy/medium tasks to a junior agent.
tags: [workflow, delegation, automation, claude-code, glm]
allowed-tools:
  - Bash
---

# cc-glm (Headless)

## When To Use

- You want to delegate repetitive CLI/codebase work (search, refactors, doc edits, running tests).
- You want a headless sub-agent loop without opening an interactive TUI.

## Important Constraints

- Work in worktrees, not canonical clones (`~/agent-skills`, `~/prime-radiant-ai`, `~/affordabot`, `~/llm-common`).
- Do not print or dump dotfiles/configs (they often contain tokens). Avoid `type cc-glm` and avoid `cat ~/.zshrc`.

## Quick Start

`cc-glm` is typically a **zsh function**, not a binary. In headless/non-interactive contexts, invoke via:

```bash
zsh -ic 'cc-glm -p "YOUR PROMPT" --output-format text'
```

If you need reliable quoting (recommended), use the wrapper script:

```bash
~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh --prompt-file /path/to/prompt.txt
```

## Fallback

If `cc-glm` is not available on the host, fall back to standard Claude Code headless mode:

```bash
claude -p "YOUR PROMPT" --output-format text
```

## Patterns That Work Well

```bash
# 1) Run a tight task in a worktree
zsh -ic 'cc-glm -p "cd /tmp/agents/bd-1234/agent-skills && rg -n \"TODO\" -S . | head" --output-format text'

# 2) Generate a patch plan (no edits)
zsh -ic 'cc-glm -p "Read docs/CANONICAL_TARGETS.md and propose a 5-step verification plan." --output-format text'
```

