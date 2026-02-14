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
- Beads epics synced to external repo
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
# Check if in canonical repo
if pwd | grep -qE "(prime-radiant-ai|agent-skills|affordabot|llm-common)$"; then
    echo "ERROR: Cannot run handoff in canonical repo"
    echo "Create worktree first: dx-worktree create <beads-id> <repo>"
    exit 1
fi

# Must be in /tmp/agents/...
if ! pwd | grep -q "/tmp/agents"; then
    echo "ERROR: Must be in worktree under /tmp/agents/"
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

### 2. Sync Beads to External Repo

```bash
# Export to JSONL in external repo
bd sync

# Verify export
cat ~/bd/.beads/issues.jsonl | grep "<epic-id>"
```

**Tech lead access:** Tech lead can import via `bd import` or view JSONL directly.

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

### 6. Create PR with V8.3 Metadata

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
```

### 7. Generate Self-Contained Prompt

Output the handoff prompt:

```
## Tech Lead Review: [Topic]

**GitHub:** https://github.com/org/repo/pull/xxx (if PR exists)
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
- **Beads:** `bd import` then `bd show bd-xxxx`
- **Docs:** Check docs/investigations/ in repo
- **PR:** <link if applicable>
```

## Happy Path (Copy-Paste)

```bash
# 1. Verify worktree
pwd | grep -q "/tmp/agents" || { echo "Use worktree!"; exit 1; }

# 2. Sync Beads
bd sync

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
```

## Integration Points

### With Beads
- Syncs epics to external JSONL
- Provides importable issue data
- Links docs to issue tracking

### With Git
- Commits investigation docs
- Pushes to remote for visibility
- Creates PR if applicable

### With GitHub
- Provides permalink to docs
- Enables async review via PR comments

## Best Practices

### Do

✅ Always run `bd sync` before handoff
✅ Include GitHub permalinks to docs
✅ Keep summary under 10 lines
✅ List specific decisions needed
✅ Provide "how to view" instructions

### Don't

❌ Reference local file paths (tech lead can't see them)
❌ Assume tech lead has your Beads database
❌ Skip committing investigation docs
❌ Forget to push to remote

## What This Skill Does

✅ Verifies worktree context (V8.3)
✅ Verifies Beads epic with subtasks
✅ Syncs Beads to external JSONL repo
✅ Creates investigation document in repo
✅ Creates handoff summary document
✅ Commits and pushes all docs
✅ Creates PR with V8.3 metadata (bd-xxxx: title, Agent: in body)
✅ Generates self-contained handoff prompt

## What This Skill DOESN'T Do

❌ Create the Beads epic (use beads-workflow first)
❌ Do the investigation (that's your work)
❌ Make decisions (tech lead's job)
❌ Create PR automatically (optional, do manually if needed)

## Example

```
User: "create handoff for the eodhd cron investigation"

AI executes:
1. bd show bd-e6cd  # Verify epic exists
2. bd sync          # Export to ~/bd/.beads/
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
