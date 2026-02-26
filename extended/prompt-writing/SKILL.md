name: prompt-writing
description: |
  Drafts robust, low-cognitive-load prompts for other agents that enforce the DX invariants:
  worktree-first, no canonical writes, and a "done gate" (dx-verify-clean).
  Use when you are writing an implementation prompt, rollout prompt, or audit prompt for any IDE agent.
tags: [workflow, prompts, orchestration, dx, safety]
allowed-tools:
  - Read
  - Bash
---

# Prompt Writing (DX-Invariants First)

## Goal

Ensure every assigned task stays on the happy path even under agent tunnel-vision:
- **No canonical writes**
- **Worktree first**
- **Done gate**
- **Bounded output / bounded PR creation** (when applicable)

## Output Contract (Always)

When asked to write a prompt for another agent, output:
1) A **single copy/paste prompt**
2) A short **PR description checklist** (optional) if the task requires “proof bundles”

## Invariant First Line (Always)

Start every drafted prompt with this exact line (including punctuation and trailing space):

```text
you're a full-stack dev agent at a tiny fintech startup: 
```

## Mandatory Prefix (Always-On)

Paste this prefix at the top of every prompt you generate:

```markdown
## DX Global Constraints (Always-On)
1) **NO WRITES** in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`
2) **Worktree first**: `dx-worktree create <id> <repo>`
3) **Before "done"**: run `~/agent-skills/scripts/dx-verify-clean.sh` (must PASS)
4) If you are about to edit anything under `~/...`, STOP and move to a worktree.
5) **Draft PR early**: open a draft PR after your FIRST real commit — do NOT wait until done
```

Recommended ordering:
1) fintech first line
2) DX global constraints block
3) plan-first gate (if complex)
4) task body
5) done gate

## Complex / Multi-Repo Tasks (Plan-First Gate)

If the task touches **2+ repos** or has **3+ phases**, include this section immediately after the prefix:

```markdown
## Plan-First Gate (Mandatory)
Before implementing, reply with:
1) Worktrees you will create (repo → beads-id)
2) Draft PRs that will exist at end (repo → title)
3) Exact commands you will run for proof (3–8 commands)

Do not start implementation until this plan is written.
```

## Done Gate (Mandatory)

Every prompt should end with:

```markdown
## Done Gate (Mandatory)
Do not claim complete until:
- All work is committed, pushed, and draft PR(s) exist (opened EARLY, not just at end)
- `~/agent-skills/scripts/dx-verify-clean.sh` PASS (canonicals clean)
```

> **Note on "draft PR early":** `worktree-push.sh` (3:15 AM) pushes committed branches nightly.
> Opening a draft PR after the first real commit makes work visible before the nightly push runs.
> Uncommitted worktree changes older than 48h are GC'd — commit or lose it (by design).

## Minimal PR Proof Bundle Template (Optional)

Use when a task is operational / infra:

```markdown
## Proof Bundle (paste into PR description)
- `dx-verify-clean`: PASS
- `dx-status`: include the summary block
- Any task-specific checks (1–5 lines each)
```

## Full Prompt Scaffold (Copy/Paste)

Use this when you need a heavier orchestration scaffold while still keeping the DX invariants:

```text
you're a full-stack dev agent at a tiny fintech startup:

## DX Global Constraints (Always-On)
1) **NO WRITES** in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`
2) **Worktree first**: `dx-worktree create <id> <repo>`
3) **Before "done"**: run `~/agent-skills/scripts/dx-verify-clean.sh` (must PASS)
4) If you are about to edit anything under `~/...`, STOP and move to a worktree.
5) **Draft PR early**: open a draft PR after your FIRST real commit — do NOT wait until done

## Objective
[One sentence: what success means.]

## Context
[Repo/app context, constraints, deadlines, links, env details.]

## Inputs
- [Links, files, PRs, tickets, logs, commands already run]

## Plan-First Gate (Mandatory)
Before implementing, reply with:
1) Worktrees you will create (repo → beads-id)
2) Draft PRs that will exist at end (repo → title)
3) Exact commands you will run for proof (3–8 commands)
Do not start implementation until this plan is written.

## Task
[Concrete deliverable(s) + acceptance criteria.]

## Done Gate (Mandatory)
Do not claim complete until:
- All work is committed, pushed, and draft PR(s) exist (opened EARLY, not just at end)
- `~/agent-skills/scripts/dx-verify-clean.sh` PASS (canonicals clean)
If blocked, explain which gate failed and the smallest next action to unblock.
```

## Frontend Verification Appendix (For UI/UX Tasks)

**When task involves frontend changes, append this section:**

```markdown
## Frontend Verification (If UI Changes)

If you modify any frontend files, you MUST:

### 1. Route Matrix
Run Playwright visual tests and capture screenshots:
```bash
pnpm --filter frontend test:visual
```

Fill in the route matrix:
| Route | Desktop | Mobile | Console Errors |
|-------|---------|--------|----------------|
| / | [pass/fail] | [pass/fail] | [count] |
| /sign-in | [pass/fail] | [pass/fail] | [count] |

### 2. Runtime Health
Check for blocking patterns:
- [ ] No "Unexpected Application Error"
- [ ] No `ClerkProvider` errors
- [ ] No `Unhandled` in console
- [ ] No `TypeError` in console

### 3. Evidence Integrity
- [ ] PR URL is valid (not `/pull/new`)
- [ ] Commit SHA matches HEAD
- [ ] Screenshots match claims

### 4. Required PR Body Section
```markdown
## Frontend Evidence
| Route | Desktop | Mobile | Status |
|-------|---------|--------|--------|
| / | ✅ | ✅ | Pass |

- Console errors: 0
- PR URL: [url]
- Commit SHA: [sha]
```

**Full template:** `~/agent-skills/templates/frontend-evidence-contract.md`
```

**Usage:** Add this appendix when delegating UI/UX work to ensure evidence contract compliance.
