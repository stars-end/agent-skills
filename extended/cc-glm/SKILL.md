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

- Default delegation mechanism for **mechanical work estimated < 1 hour**:
  - search/triage, small refactors, doc edits, script wiring, low-risk CI fixes, adding tests
- You want a headless sub-agent loop without opening an interactive TUI.

## Delegation Boundary (DX V8.1)

**Delegate (default) if < 1 hour and mechanical.**

Do **not** delegate (or delegate only after you tighten scope) when:
- security-sensitive changes (auth, crypto, secrets, permissions)
- architectural decisions / broad refactors
- ambiguous requirements or high blast-radius changes

The orchestrator (you) remains responsible for:
- reviewing diffs
- running/confirming validation
- committing/pushing with required trailers

## Important Constraints

- Work in worktrees, not canonical clones (`~/agent-skills`, `~/prime-radiant-ai`, `~/affordabot`, `~/llm-common`).
- Do not print or dump dotfiles/configs (they often contain tokens).
- The delegate must **not** run `git commit`, `git push`, or open PRs.

## Recommended Setup (Deterministic)

To avoid relying on shell init files, prefer exporting `CC_GLM_AUTH_TOKEN` (and optionally `CC_GLM_BASE_URL`, `CC_GLM_MODEL`).

When set, `cc-glm-headless.sh` will invoke `claude` directly with these env vars (no `zsh -ic` needed).

If you use 1Password, you can also set `ZAI_API_KEY` as an `op://...` reference (or set `CC_GLM_OP_URI`) and `cc-glm-headless.sh` will resolve it via `op read` at runtime.

## Preferred Entry Point (Recommended)

Use the DX wrapper so prompts are V8.1 compliant and logs are kept:

```bash
dx-delegate --beads bd-xxxx --repo repo-name --prompt-file /path/to/task.txt
```

Logs are written under: `/tmp/dx-delegate/<beads-id>/...`

## Quick Start

`cc-glm` is typically a **zsh function**, not a binary. In headless/non-interactive contexts, invoke via:

```bash
zsh -ic 'cc-glm -p "YOUR PROMPT" --output-format text'
```

If you need reliable quoting (recommended), use the wrapper script:

```bash
~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh --prompt-file /path/to/prompt.txt
```

## DX-Compliant Prompt Template

Use this template for delegated work (copy/paste):

```text
Beads: bd-xxxx
Repo: repo-name
Worktree: /tmp/agents/bd-xxxx/repo-name
Agent: cc-glm

Hard constraints:
- Work ONLY in the worktree path above (never touch canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common}).
- Do NOT run git commit/push. Do NOT open PRs.
- Output a unified diff patch, plus validation commands, plus brief risk notes.

Task:
- (1-5 bullets of the exact change)

Expected outputs:
- Patch diff (unified)
- Commands to validate (lint/tests)
- Notes: any edge cases or follow-ups
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
