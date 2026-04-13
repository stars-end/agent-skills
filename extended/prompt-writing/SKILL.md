---
name: prompt-writing
description: |
  Draft self-contained prompts for delegated agents with cross-VM-safe context.
  MUST BE USED when assigning work to another agent (implementation, QA, rollout, or audit).
  Enforces: worktree-first, no canonical writes, Beads traceability (epic/subtask/dependencies), MCP routing expectations, and required PR artifacts (PR_URL + PR_HEAD_SHA).
  Trigger phrases include: "assign to another agent", "write a one-shot prompt", "dispatch this", "prepare autonomous prompt", "QA agent prompt", "parallelize work to cloud", and "assign to jules".
tags: [workflow, prompts, orchestration, dx, safety]
allowed-tools:
  - Read
  - Bash
---

# Prompt Writing (Delegation Contract First)

## Goal

Generate a prompt another agent can execute autonomously without local-machine assumptions:
- Cross-VM safe context via GitHub PR link + commit SHA
- Self-contained requirements and acceptance criteria
- Beads traceability (epic/subtask/dependencies)
- Hard delivery contract: `PR_URL` + `PR_HEAD_SHA`

## Re-Scoped Role (2026-03)

`prompt-writing` is the canonical **outbound dispatch contract** skill.
It replaces prompt-shaping usage that previously lived in:
- `parallelize-cloud-work` (archived)
- `jules-dispatch` (archived)

## Boundary: Review Lanes

`prompt-writing` is for delegation prompts that ask another agent to implement,
repair, verify, or ship code changes. For inbound reviewer lanes, use
`dx-review --template <smoke|code-review|architecture-review|security-review>`
instead of embedding reviewer prompt bodies manually.

## Lifecycle Modes

Use one explicit mode in each generated prompt:
- `MODE: initial_implementation`
- `MODE: pr_repair`
- `MODE: qa_pass`
- `MODE: ci_repair`
- `MODE: review_fix_redispatch`

## Trigger Conditions (Mandatory)

Use this skill whenever user intent is delegation to another agent, including:
- "assign to another agent"
- "write me a one-shot prompt"
- "prepare a prompt for QA/dev agent"
- "dispatch this work"
- "make this autonomous for jr agent"
- "parallelize work to cloud"
- "start cloud sessions"
- "assign this to jules"
- "dispatch to jules"

Do not wait for the user to say "prompt-writing" explicitly if delegation intent is clear.

## Core Requirements (Always)

Every generated delegation prompt MUST enforce:

0) **Orchestrator push-first / delegate pull-first workflow**
- Orchestrator MUST push context (docs/specs/plans) to GitHub BEFORE generating prompt
- Use resulting `PR_HEAD_SHA` or `PR_URL` in prompt
- **Delegate MUST `git fetch` the remote PR branch and read specs/docs from that fetched state before doing anything else.**
- Delegate must NOT assume the PR branch exists locally — always fetch + checkout first
- Never embed file contents in prompt text

0.5) **Secret-auth invariant (always-on)**
- Delegated agents must not use raw `op read`, `op item get`, `op item list`, or `op whoami` for routine secret access.
- Delegated agents must use cache/service-account helpers, preferably `DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached ...`.
- On cache/service-account miss, delegated agents must fail closed with a blocker and must not fall back to GUI-backed OP.
- Delegated agents must not run OP retry loops unless the assignment is explicitly an auth-repair task.

1) **Cross-VM accessibility**
- Do not reference `/Users/...`, `/tmp/...`, or other local-only paths as source of truth.
- Primary context must be reachable by URL and commit, ideally:
  - `PR_URL`
  - `PR_HEAD_SHA`
  - repo-relative file paths in that PR/branch.

2) **Self-contained task definition**
- Objective, scope boundaries, acceptance criteria, and stop conditions must be in the prompt.
- Delegate must not need hidden context from local docs.

3) **Beads documentation contract**
- Include and require explicit identifiers:
  - `BEADS_EPIC`
  - `BEADS_SUBTASK`
  - `BEADS_DEPENDENCIES` (or `none`)
- If unknown, force delegate to return `BLOCKED: MISSING_BEADS_CONTEXT`.

4) **Worktree + canonical safety**
- No writes in canonical clones.
- Worktree required before edits.

5) **PR artifact return contract**
- Final response MUST include:
  - `PR_URL: https://github.com/<org>/<repo>/pull/<n>`
  - `PR_HEAD_SHA: <40-char sha>`
- If missing, delegate must return blocker with exact next commands.

6) **Tool routing contract for the delegated task**
- semantic discovery -> `llm-tldr` (V8.6)
- exact static analysis -> `llm-tldr`
- durable cross-agent memory -> Beads (`bdx remember` or closed `memory` issues)
- symbol-aware editing -> `serena`
- If a delegated agent intentionally skips the expected tool, it must return `Tool routing exception: <reason>`

7) **dx-loop-first contract for chained/non-trivial work**
- When the task is chained Beads work, multi-step, or expected to need implement/review baton flow, the prompt should make `dx-loop` the primary execution surface.
- Prompts should tell delegates to use:
  - `dx-loop status --beads-id <id>` as the default task lookup surface
  - `dx-loop explain --beads-id <id>` as the default blocker diagnosis surface
- Prompts should explicitly separate:
  - `CLASS: product`
  - `CLASS: dx_loop_control_plane`
- Direct/manual implementation should be framed as fallback only when `dx-loop` itself is the active blocker or a tiny end-stage repair is clearly justified.

8) **Memory retrieval for high-friction domains**
- For cross-VM, cross-repo, vendor/API, infra/auth/workflow, or repeated-friction work, require targeted Beads memory lookup before execution:
  - `bdx memories <keyword> --json`
  - `bdx search <keyword> --label memory --status all --json`
  - `bdx show <memory-id> --json`
  - `bdx comments <memory-id> --json`
- Do not require memory lookup for trivial routine edits.
- Clarify in prompts: `bdx comments add` is task-local history; durable cross-agent memory belongs in `bdx remember` or closed `memory` issues.

## Outcome Enforcement Options

Generated prompts should set these options explicitly when relevant:
- `UPDATE_EXISTING_PR: true|false`
- `PR_STATE_TARGET: draft|ready_for_review`
- `REQUIRE_MERGE_READY: true|false`
- `SELF_REPAIR_ON_CHECK_FAILURE: true|false`

## Final Response Modes

Generated prompts should include one final response mode:
- `FINAL_RESPONSE_MODE: standard`
- `FINAL_RESPONSE_MODE: tech_lead_review`
- `FINAL_RESPONSE_MODE: qa_findings`
- `FINAL_RESPONSE_MODE: ci_repair_report`

## Output Contract (Always)

When user asks for a delegated prompt, return:
1) One copy/paste prompt
2) Optional short "Dispatcher Notes" (only if needed)
3) Nothing else unless user asks

## dx-loop Prompt Pattern (Use When Applicable)

For `dx-loop`-first product prompts, include language equivalent to:

- `dx-loop` is the primary execution surface for this task
- use `dx-loop` first because this is chained Beads work with a non-trivial implement/review baton
- use direct/manual implementation only if `dx-loop` itself is the active blocker or after `dx-loop` has already produced a concrete review verdict that justifies a narrow repair
- if blocked, check:
  - `dx-loop status --beads-id <BEADS_SUBTASK>`
  - `dx-loop explain --beads-id <BEADS_SUBTASK>`

The blocker contract should classify the result as:
- `CLASS: product`
- `CLASS: dx_loop_control_plane`

This keeps product bugs separate from orchestration bugs and reduces wave-internals burden on the delegate.

## Before Emitting (Mandatory)

STOP if ANY check fails:

- [ ] `BEADS_EPIC` is concrete ID (e.g., `bd-sg2v.13`), not `<bd-...>`
- [ ] `BEADS_SUBTASK` is concrete ID, not placeholder
- [ ] No `/Users/...`, `/tmp/...`, or `/home/...` local paths
- [ ] Paths are repo-relative or GitHub URLs
- [ ] If Beads IDs are unknown, resolve with targeted lookup first: `bdx show <known-id> --json`, `bdx search ...`, or BV `robot-plan`; use `bdx ready --limit ...` only for manual queue browsing, not orchestration loops or health probes
- [ ] For cross-VM/cross-repo/vendor/API/infra/auth/workflow work, memory retrieval commands are included and scoped (`bdx memories`, `bdx search --label memory`, then targeted `show/comments`)

If you can't resolve: return blocker, don't emit prompt.

## Required Prompt Skeleton

**NOTE**: Skeleton shows structure. Actual dispatched prompts must have concrete values.

```markdown
you're a full-stack dev agent at a tiny fintech startup:

## DX Global Constraints (Always-On)
1) NO WRITES in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`
2) Worktree first: `dx-worktree create bd-sg2v.13.1 prime-radiant-ai`
3) Before "done": run `~/agent-skills/scripts/dx-verify-clean.sh` (must PASS)
4) Open draft PR after first real commit
5) Final response MUST include `PR_URL` and `PR_HEAD_SHA`

## Absolute Secret-Auth Safety Rules (Always-On)
- DO NOT run raw `op read`, `op item get`, `op item list`, or `op whoami` for routine agent secret access.
- Use cached/service-account helpers only (prefer `DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached ...`).
- If cache/service-account auth is unavailable, return `BLOCKED: secret_auth_cache_unavailable`.
- Do not run OP retry loops unless task scope is explicitly auth repair.

## Assignment Metadata (Required)
- MODE: initial_implementation
- BEADS_EPIC: bd-sg2v.13  # ← actual ID, never <bd-...>
- BEADS_SUBTASK: bd-sg2v.13.1
- BEADS_DEPENDENCIES: bd-sg2v.12
- FEATURE_KEY: bd-sg2v.13.1

## Outcome Enforcement (Required)
- UPDATE_EXISTING_PR: false
- PR_STATE_TARGET: draft
- REQUIRE_MERGE_READY: false
- SELF_REPAIR_ON_CHECK_FAILURE: true
- FINAL_RESPONSE_MODE: standard

## Cross-VM Source of Truth (Required)
- PR_URL: https://github.com/stars-end/prime-radiant-ai/pull/937
- PR_HEAD_SHA: abc123def456789...
- Repo paths to read first:
   - frontend/src/components/RootLayout.tsx
   - frontend/package.json

If PR_URL/PR_HEAD_SHA is not available yet, create/refresh branch and open draft PR before finishing.

## Step 0: Fetch Remote PR (MANDATORY — do before anything else)

    # Fetch the orchestrator's spec/docs PR — do NOT skip this
    git fetch origin pull/937/head:pr-937
    git checkout pr-937

Then read every file listed under "Repo paths to read first" above.
Only after reading all specs/docs, proceed to Step 1 (worktree creation).

## Objective
Implement shadcn/ui foundation with design tokens for V2 routes.

## Scope
- In scope: Tailwind v4 setup, shadcn/ui v4 install, token configuration
- Out of scope: MUI removal, AG Grid migration

## Acceptance Criteria
1) `pnpm --filter frontend build` succeeds
2) `pnpm --filter frontend type-check` passes
3) No MUI imports in modified files

## Execution Plan (Mandatory)
Before coding, reply with:
1) Worktree path + branch name
2) Files to modify
3) Validation commands

## Required Deliverables
- Code changes committed and pushed
- Draft PR created/updated
- Validation summary
- Return block:
   - PR_URL: https://github.com/stars-end/prime-radiant-ai/pull/937
   - PR_HEAD_SHA: abc123def456789...
   - BEADS_SUBTASK: bd-sg2v.13.1

## Blockers Protocol
If blocked, return exactly:
- BLOCKED: <reason_code>
- NEEDS: <single dependency/info needed>
- NEXT_COMMANDS:
   1) bdx show bd-sg2v.13
   2) bdx search "<targeted keywords>" --json

## Done Gate (Mandatory)
Do not claim complete until:
- Changes committed/pushed
- Draft PR exists
- `dx-verify-clean.sh` passes
- Final response includes PR_URL and PR_HEAD_SHA
```

## Cross-VM Guardrail (Critical)

Two-PR pattern:
1. **Orchestrator's context PR** — docs/specs/plan pushed to GitHub first
2. **Delegate's implementation PR** — code changes pushed by delegate

Prompts that reference local absolute paths as required inputs are invalid for cross-VM delegation.
Orchestrator must push context to GitHub BEFORE generating the prompt.

**Delegate's first action MUST be to fetch and read the remote PR:**
- `git fetch origin pull/<N>/head:<branch>` or `git fetch origin <branch>`
- Read all listed spec/doc/plan files from the fetched state
- Only then proceed with worktree creation and implementation
- Do NOT skip this step — the PR branch is the authoritative spec source

## Hardened Rule

Prompts with `<bd-...>` placeholders or local paths in required fields are INVALID.
Resolve context BEFORE generating, not during delegate execution.

## Relationship to `tech-lead-handoff`

- `prompt-writing`: prepares autonomous prompts for another agent to execute.
- `tech-lead-handoff`: packages completed investigation/planning for human tech-lead review.

Use `prompt-writing` for delegation. Use `tech-lead-handoff` for approval handoffs.
