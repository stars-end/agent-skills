---
name: tech-lead-handoff
description: |
  Create comprehensive handoff for tech lead review with Beads epic sync, committed docs, and self-contained prompt.
  MUST BE USED when completing investigation, incident analysis, or feature planning that needs tech lead approval.
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

<!-- Feature-Key: bd-0bt4 -->

Create self-contained handoff for tech lead review with guaranteed visibility.

## Purpose

Ensures tech lead can review your work without needing access to your local environment:
- Beads epics verified in canonical `~/bd` backend
- Investigation docs committed and pushed to GitHub
- Self-contained prompt with all context included

## When to Use This Skill

**Trigger phrases:**
- "handoff"
- "tech lead review"
- "review this"
- "create handoff"
- "for review"

**Use when:**
- Completing incident investigation
- Finishing feature planning
- Creating fix plans that need approval
- Ending a session with significant deliverables

## Workflow

### 0. Worktree Enforcement (FAIL FAST)

Before any git operations, verify worktree context:

```bash
# Must be in worktree under /tmp/agents/ (check this FIRST)
if ! pwd | grep -q "/tmp/agents"; then
    echo "ERROR: Must be in worktree under /tmp/agents/"
    echo "Current: $(pwd)"
    echo "Create worktree first: dx-worktree create <beads-id> <repo>"
    exit 1
fi

# Verify not somehow in canonical path (belt-and-suspenders)
if pwd | grep -qE "^$HOME/(prime-radiant-ai|agent-skills|affordabot|llm-common)$"; then
    echo "ERROR: Cannot run handoff in canonical repo"
    exit 1
fi
```

### 1. Verify Beads Epic Exists

```bash
# Check for epic
bd show <epic-id>

# If no epic, create one
bd create --title "<title>" --type epic --priority 1
```

Ensure subtasks exist with clear descriptions.

### 2. Verify Beads in Canonical Repo

```bash
(beads-dolt dolt test --json && beads-dolt status --json)
(beads-dolt show <epic-id>)
```

**Tech lead access:** Tech lead can run `beads-dolt show <epic-id>` directly.

### 3. Create Investigation Document

Create comprehensive doc in repo:

```bash
# Create investigation directory if needed
mkdir -p docs/investigations/

# Create doc with date prefix
docs/investigations/$(date +%Y-%m-%d)-<topic>-analysis.md
```

**Document structure:**
```markdown
# [Topic] Analysis

**Date:** YYYY-MM-DD
**Beads Epic:** bd-xxxx
**Status:** Ready for review

## Executive Summary
1-2 paragraph summary

## Root Cause Analysis
Evidence-based analysis

## Evidence
Database queries, code references, logs

## Fix Plan
Beads epic + subtasks with acceptance criteria

## Appendix
Commands, references
```

### 4. Create Handoff Summary

Create `docs/investigations/TECHLEAD-REVIEW-<topic>.md`:

```markdown
# Tech Lead Review: [Topic]

**Handoff Date:** YYYY-MM-DD
**Beads Epic:** bd-xxxx
**Full Doc:** docs/investigations/YYYY-MM-DD-<topic>-analysis.md

## Quick Summary
- **What happened:** 1 sentence
- **Root cause:** 1 sentence
- **Fix plan:** Epic ID + subtask count

## Evidence Summary
| Evidence | Source | Finding |
|----------|--------|---------|
| ... | ... | ... |

## Beads Structure
```
○ bd-xxxx [EPIC] Title [Priority]
  ↳ bd-xxxx.1: Subtask 1
  ↳ bd-xxxx.2: Subtask 2
```

## Files Changed
| File | Changes |

## Decisions Required
1. Approve fix plan?
2. Priority of implementation?
3. Any concerns?

## How to View
- Beads: `bd show bd-xxxx` (after import)
- Full doc: `docs/investigations/YYYY-MM-DD-<topic>-analysis.md`
- GitHub: https://github.com/org/repo/blob/.../docs/investigations/...
```

### 5. Commit and Push

```bash
# Stage investigation docs
git add docs/investigations/

# Commit with Feature-Key
git commit -m "docs: Add [topic] investigation for tech lead review

- Root cause analysis with evidence
- Fix plan with Beads epic bd-xxxx
- Self-contained handoff prompt

Feature-Key: bd-xxxx
Agent: <agent-id>"

# Push to remote
git push origin <branch>
```

### 6. Create PR with V8.3 Metadata (REQUIRED BEFORE HANDOFF PROMPT)

PR MUST include:
- Title: `bd-xxxx: Description`
- Body: `Agent: <agent-id>`

```bash
gh pr create --title "bd-xxxx: Description of changes" --body "$(cat <<'EOF'
## Summary
- Bullet points of changes

## Test Plan
- How to verify

Agent: <your-agent-id>
EOF
)"

# REQUIRED artifacts for cross-VM handoff
PR_URL=$(gh pr view --json url -q .url)
PR_HEAD_SHA=$(git rev-parse HEAD)

test -n "$PR_URL" || { echo "BLOCKED: PR_NOT_CREATED"; exit 1; }
test -n "$PR_HEAD_SHA" || { echo "BLOCKED: MISSING_HEAD_SHA"; exit 1; }
```

### 7. Generate Self-Contained Prompt (PR_URL + PR_HEAD_SHA REQUIRED)

Only generate the handoff prompt after:
1. Docs are committed and pushed.
2. Beads evidence/status is updated.
3. PR exists and `PR_URL` / `PR_HEAD_SHA` are captured.

Output the handoff prompt:

```
## Tech Lead Review: [Topic]

**PR_URL:** https://github.com/org/repo/pull/xxx
**PR_HEAD_SHA:** <40-char sha>
**Beads Epic:** bd-xxxx
**Investigation:** docs/investigations/YYYY-MM-DD-<topic>-analysis.md

### Summary
- **What happened:** <1-2 sentences>
- **Root cause:** <1-2 sentences with evidence>
- **Fix plan:** bd-xxxx with N subtasks

### Evidence
- <Key evidence item 1>
- <Key evidence item 2>
- <Key evidence item 3>

### Beads Structure
<Copy from TECHLEAD-REVIEW doc>

### Decisions Needed
1. <Decision 1>
2. <Decision 2>

### How to View
- **Beads:** `beads-dolt show bd-xxxx`
- **Docs:** Check docs/investigations/ in repo
- **PR:** <required link>
- **Commit:** <required head sha>
```

If PR is not created yet, output this exact blocker format and STOP:

```text
BLOCKED: PR_NOT_CREATED
Next action:
1) git push origin <branch>
2) gh pr create --title "bd-xxxx: <title>" --body "Agent: <agent-id>"
3) Re-run handoff output with PR_URL and PR_HEAD_SHA
```

## Happy Path (Copy-Paste)

```bash
# 1. Verify worktree
pwd | grep -q "/tmp/agents" || { echo "Use worktree!"; exit 1; }

# 2. Verify Beads
(beads-dolt dolt test --json && beads-dolt show bd-xxxx)

# 3. Check git status
git status

# 4. Stage changes
git add docs/investigations/

# 5. Commit with trailers
git commit -m "docs: Add investigation for [topic]

Feature-Key: bd-xxxx
Agent: <agent-id>"

# 6. Push
git push origin $(git branch --show-current)

# 7. Create PR
gh pr create --title "bd-xxxx: [title]" --body "$(cat <<'EOF'
## Summary
- Investigation of [topic]

Agent: <agent-id>
EOF
)"

# 8. Capture required review artifacts
PR_URL=$(gh pr view --json url -q .url)
PR_HEAD_SHA=$(git rev-parse HEAD)
test -n "$PR_URL" || { echo "BLOCKED: PR_NOT_CREATED"; exit 1; }
echo "PR_URL=$PR_URL"
echo "PR_HEAD_SHA=$PR_HEAD_SHA"
```

## Integration Points

### With Beads
- Verifies epics in canonical `~/bd` backend
- Provides importable issue data
- Links docs to issue tracking

### With Git
- Commits investigation docs
- Pushes to remote for visibility
- Creates PR before handoff prompt generation (required)

### With GitHub
- Provides permalink to docs
- Enables async review via PR comments

## Best Practices

### Do

✅ Always verify `beads-dolt dolt test --json` before handoff
✅ Include GitHub permalinks to docs
✅ Include `PR_URL` and `PR_HEAD_SHA` in the handoff prompt
✅ Keep summary under 10 lines
✅ List specific decisions needed
✅ Provide "how to view" instructions

### Don't

❌ Reference local file paths (tech lead can't see them)
❌ Assume tech lead has your Beads database
❌ Skip committing investigation docs
❌ Forget to push to remote
❌ Output handoff prompt without `PR_URL` and `PR_HEAD_SHA`

## What This Skill Does

✅ Verifies worktree context (V8.3)
✅ Verifies Beads epic with subtasks
✅ Verifies Beads state in canonical `~/bd` repo
✅ Creates investigation document in repo
✅ Creates handoff summary document
✅ Commits and pushes all docs
✅ Creates PR with V8.3 metadata (bd-xxxx: title, Agent: in body)
✅ Generates self-contained handoff prompt with required `PR_URL` + `PR_HEAD_SHA`

## What This Skill DOESN'T Do

❌ Create the Beads epic (use beads-workflow first)
❌ Do the investigation (that's your work)
❌ Make decisions (tech lead's job)
❌ Complete handoff output without an existing PR URL

## Example

```
User: "create handoff for the eodhd cron investigation"

AI executes:
1. bd show bd-e6cd  # Verify epic exists
2. (beads-dolt dolt test --json && beads-dolt show bd-xxxx)
3. Verify docs/investigations/2026-02-14-eodhd-cron-failure-analysis.md
4. Verify docs/investigations/TECHLEAD-REVIEW-eodhd-cron-failure.md
5. git add docs/investigations/
6. git commit -m "docs: Add EODHD cron failure investigation..."
7. git push origin master
8. Output self-contained prompt with GitHub links

Output:
## Tech Lead Review: EODHD Cron Failure

**GitHub:** https://github.com/fnthaw/prime-radiant-ai/blob/master/docs/investigations/...
**Beads Epic:** bd-e6cd
**Investigation:** docs/investigations/2026-02-14-eodhd-cron-failure-analysis.md

### Summary
- **What happened:** cron_eod at 23:00 UTC on Feb 13 didn't execute...
...
```

## Troubleshooting

### "Beads sync shows 0 issues"

Check that issues exist in local database:
```bash
bd list --epic
```

### "Tech lead can't see docs"

Ensure docs are pushed:
```bash
git status
git log --oneline -3
git push origin <branch>
```

### "Prompt references local paths"

Replace local paths with GitHub permalinks:
```bash
# Get permalink
gh api repos/{owner}/{repo}/contents/docs/investigations/file.md --jq '.html_url'
```

---

**Last Updated:** 2026-02-14
**Skill Type:** Workflow
**Average Duration:** 2-3 minutes
