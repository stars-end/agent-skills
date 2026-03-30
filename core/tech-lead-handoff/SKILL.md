---
name: tech-lead-handoff
description: |
  Create comprehensive handoff for tech lead review with Beads sync, PR artifacts, and self-contained review package.
  MUST BE USED when returning completed work to a tech lead/orchestrator for review (investigation OR implementation return).
  Use when user says "handoff", "tech lead review", "review this", "create handoff", or after completing significant work.
tags: [workflow, handoff, review, beads, documentation]
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(git:*)
  - Bash(bd:*)
  - Bash(gh:*)
---

# Tech Lead Handoff

Create a review-ready package that works cross-VM and does not depend on local paths.

## Modes

- `MODE: investigation`
  - for incident analysis, planning, and investigation outcomes
  - requires `docs/investigations/*` artifacts
- `MODE: implementation_return`
  - for implementer-to-orchestrator code return handoff
  - does NOT require investigation docs

## Trigger Conditions

Use this skill when user intent is handoff/review packaging:
- "handoff"
- "tech lead review"
- "review this"
- "create handoff"
- "for review"

## Shared Required Artifacts (Both Modes)

- `PR_URL`
- `PR_HEAD_SHA`
- `BEADS_EPIC` (or `none`)
- `BEADS_SUBTASK` (or feature id)
- `BEADS_DEPENDENCIES` (or `none`)
- Validation summary (commands + pass/fail)
- Tool Evidence summary:
  - tools used: `llm-tldr`, `serena`
  - or `Tool routing exception: <reason>`
- Changed files summary
- Open blockers / decisions needed
- How-to-review checklist

## Workflow

### 0. Worktree Enforcement (Fail Fast)

```bash
if ! pwd | grep -q "/tmp/agents"; then
  echo "ERROR: Must run from worktree under /tmp/agents"
  exit 1
fi

if pwd | grep -qE "^$HOME/(prime-radiant-ai|agent-skills|affordabot|llm-common)$"; then
  echo "ERROR: Cannot run handoff in canonical repo"
  exit 1
fi
```

### 1. Select Mode (Required)

Set mode explicitly before packaging:

```bash
# Choose exactly one
MODE=investigation
# or
MODE=implementation_return
```

If mode is ambiguous, stop and ask for mode.

### 2. Verify Beads + Canonical Health

```bash
(beads-dolt dolt test --json && beads-dolt status --json)

# Verify work item(s) referenced by this handoff
bd show <beads-id>
```

### 3. Ensure PR Exists and Capture Review Artifacts

PR must exist before final handoff output.

```bash
# Push current branch first
git push origin "$(git branch --show-current)"

# Create PR if needed (title must include Feature-Key; body must include Agent)
gh pr create --title "bd-xxxx: <title>" --body "Agent: <agent-id>"

PR_URL=$(gh pr view --json url -q .url)
PR_HEAD_SHA=$(git rev-parse HEAD)

test -n "$PR_URL" || { echo "BLOCKED: PR_NOT_CREATED"; exit 1; }
test -n "$PR_HEAD_SHA" || { echo "BLOCKED: MISSING_HEAD_SHA"; exit 1; }
```

### 4A. Mode Path: `investigation`

Required in this mode:

1. Create investigation doc:
- `docs/investigations/YYYY-MM-DD-<topic>-analysis.md`

2. Create review summary doc:
- `docs/investigations/TECHLEAD-REVIEW-<topic>.md`

3. Commit and push docs before output:

```bash
git add docs/investigations/
git commit -m "docs: add investigation handoff for tech lead review

Feature-Key: bd-xxxx
Agent: <agent-id>"
git push origin "$(git branch --show-current)"
```

### 4B. Mode Path: `implementation_return`

Required in this mode:

1. Do NOT force `docs/investigations/*` creation.
2. Build concise implementation return package containing:
- `PR_URL`, `PR_HEAD_SHA`
- Beads linkage (`BEADS_EPIC`, `BEADS_SUBTASK`, `BEADS_DEPENDENCIES`)
- Validation summary
- Changed files summary
- Remaining risks/blockers
- Decisions needed
- How-to-review checklist

Optional:
- Add `docs/handoffs/TECHLEAD-RETURN-<beads-id>.md` if persistent handoff record is needed.

### 5. Output Final Handoff Payload (Mode-Specific)

#### Output Template: `MODE=investigation`

**NOTE**: Template shows structure. Actual handoffs must have concrete values.

```markdown
## Tech Lead Review (Investigation)

- MODE: investigation
- PR_URL: https://github.com/stars-end/agent-skills/pull/123  # ← actual URL
- PR_HEAD_SHA: abc123def456789...  # ← 40-char SHA
- BEADS_EPIC: bd-sg2v.13  # ← actual ID, never <bd-...>
- BEADS_SUBTASK: bd-sg2v.13.1
- BEADS_DEPENDENCIES: bd-sg2v.12
- Investigation Doc: docs/investigations/2026-03-08-frontend-analysis.md
- Review Summary Doc: docs/investigations/TECHLEAD-REVIEW-frontend.md

### Validation
- pnpm --filter frontend build: PASS
- pnpm --filter frontend type-check: PASS

### Tool Evidence
- Used: <tool list>
- Routing exception: none

### Decisions Needed
1. Approve shadcn/ui adoption for V2 routes
2. Confirm AG Grid migration timeline

### How To Review
1. Open PR
2. Read docs/investigations artifacts
3. Verify Beads state
```

#### Output Template: `MODE=implementation_return`

**NOTE**: Template shows structure. Actual handoffs must have concrete values.

```markdown
## Tech Lead Review (Implementation Return)

- MODE: implementation_return
- PR_URL: https://github.com/stars-end/prime-radiant-ai/pull/937
- PR_HEAD_SHA: def456abc123789...
- BEADS_EPIC: bd-sg2v.13
- BEADS_SUBTASK: bd-sg2v.13.1
- BEADS_DEPENDENCIES: none

### Validation
- pnpm --filter frontend build: PASS
- pnpm --filter frontend test: PASS
- dx-verify-clean.sh: PASS

### Tool Evidence
- Used: <tool list>
- Routing exception: none

### Changed Files Summary
- frontend/package.json: Added shadcn/ui dependencies
- frontend/tailwind.config.ts: Configured Tailwind v4 tokens
- frontend/src/components/RootLayout.tsx: Replaced MUI with shadcn

### Risks / Blockers
- None - ready for review

### Decisions Needed
1. Merge timing (before or after bd-sg2v.13.2)

### How To Review
1. Open PR and inspect files changed
2. Check validation evidence
3. Confirm Beads linkage and completion state
```

## Blocker Protocol (Exact)

If required artifacts are missing, output exactly:

```text
BLOCKED: <reason_code>
NEEDS: <single missing dependency/info>
NEXT_COMMANDS:
1) <command>
2) <command>
```

## Relationship to Prompt Writing

- `prompt-writing`: outbound dispatch contract to implementer/QA agent.
- `tech-lead-handoff`: inbound return package back to orchestrator/tech lead.

Keep these roles separate.

## Before Emitting (Mandatory)

STOP if ANY check fails:

- [ ] `BEADS_EPIC` is concrete ID or `"none"`, not `<bd-...>`
- [ ] `BEADS_SUBTASK` is concrete ID, not placeholder
- [ ] `PR_URL` is actual GitHub URL, not `<url>`
- [ ] `PR_HEAD_SHA` is 40-char SHA, not `<sha>`
- [ ] No `/Users/...`, `/tmp/...`, or local paths in handoff content

If you can't resolve: return blocker, don't emit handoff.

## Hardened Rule

Handoffs with `<bd-...>` placeholders or `<url>`/`<sha>` placeholders in required fields are INVALID.
Resolve context BEFORE generating handoff, not during review.

---

**Last Updated:** 2026-03-08
**Skill Type:** Workflow
**Average Duration:** 2-4 minutes
