# V8 Process Fixes Specification

**Feature-Key:** bd-v8-process-fixes
**Priority:** P1
**Estimated Scope:** 3 files, ~100 lines

## Problem Statement

V8 compliance audit (2026-02-08) revealed systematic gaps in agent workflow enforcement:

| Issue | Severity | Evidence |
|-------|----------|----------|
| Missing `Feature-Key:` trailer | High | 6/7 PRs in prime-radiant-ai lack it |
| Missing `Agent:` trailer | Medium | All agent commits missing attribution |
| Agents work in canonical repos | High | "Recovery Agent" commits in PRs #707, #699 |
| PR descriptions template-only | Low | #707, #708 have unfilled templates |

## Root Cause

1. **Pre-commit hook only blocks commits** — doesn't enforce trailers
2. **Agent skills don't auto-add trailers** — `sync-feature-branch` skill missing enforcement
3. **No CI enforcement** — DX Guardrails workflow is warn-only, doesn't block

## Solution Design

### 1. Enhance `sync-feature-branch` Skill

**File:** `~/agent-skills/core/sync-feature-branch/SKILL.md`

Add mandatory trailer injection to the commit message template:

```yaml
# In the skill's commit flow, ensure message includes:
commit_message: |
  ${COMMIT_TITLE}

  ${COMMIT_BODY}

  Feature-Key: ${BEADS_ID}
  Agent: ${AGENT_NAME:-Claude}
```

**Implementation:**
- Extract `BEADS_ID` from branch name (pattern: `feature-bd-XXXX`)
- If no beads ID found, FAIL with message: "Cannot commit without Feature-Key. Create beads issue first: `bd create`"
- Add `Agent:` trailer with agent identifier

### 2. Enhance Pre-commit Hook

**File:** `~/agent-skills/scripts/install-canonical-precommit.sh`

Add trailer validation to the hook (after the canonical check):

```bash
# After canonical check passes (we're in a worktree), validate trailers
COMMIT_MSG_FILE="$1"  # For prepare-commit-msg hook
if [ -n "$COMMIT_MSG_FILE" ]; then
  if ! grep -q "^Feature-Key: bd-" "$COMMIT_MSG_FILE"; then
    echo "⚠️  WARNING: Commit missing Feature-Key trailer" >&2
    echo "   Add: Feature-Key: bd-XXXX" >&2
  fi
fi
```

**Note:** This should be a `prepare-commit-msg` or `commit-msg` hook, not pre-commit. Consider adding a separate hook file.

### 3. Upgrade DX Guardrails to Blocking (Optional)

**File:** `.github/workflows/dx-guardrails.yml` (in each repo)

Change from warn-only to blocking for Feature-Key:

```yaml
- name: Check Feature-Key
  run: |
    # Get all commits in PR
    COMMITS=$(gh pr view ${{ github.event.pull_request.number }} --json commits -q '.commits[].messageBody')
    if ! echo "$COMMITS" | grep -q "Feature-Key:"; then
      echo "::error::PR commits missing Feature-Key trailer"
      exit 1
    fi
```

**Risk:** May block legitimate PRs. Recommend keeping as warning initially, promote to error after 1 week burn-in.

## Implementation Checklist

- [ ] **Task 1:** Update `sync-feature-branch` SKILL.md
  - Add Feature-Key extraction from branch name
  - Add Agent trailer injection
  - Add validation that fails without beads ID

- [ ] **Task 2:** Create `commit-msg` hook in `install-canonical-precommit.sh`
  - Validate Feature-Key presence (warning only)
  - Print remediation instructions

- [ ] **Task 3:** Update `create-pull-request` skill
  - Auto-populate PR description from commits
  - Extract Feature-Key and link to beads issue

- [ ] **Task 4:** (Optional) Upgrade DX Guardrails
  - Add Feature-Key check
  - Keep as warning for burn-in period

## Acceptance Criteria

1. `sync-feature-branch` skill refuses to commit without Feature-Key
2. Agent commits automatically include `Agent: Claude` trailer
3. PR descriptions auto-populated with summary (not template-only)
4. Pre-commit hook warns on missing Feature-Key

## Files to Modify

```
~/agent-skills/core/sync-feature-branch/SKILL.md
~/agent-skills/core/create-pull-request/SKILL.md
~/agent-skills/scripts/install-canonical-precommit.sh
```

## One-Shot Instructions for Agent

```
You are implementing V8 process fixes per this spec.

1. Create worktree: dx-worktree create bd-v8-process-fixes agent-skills
2. Create beads issue: bd create "V8: Enforce Feature-Key and Agent trailers" --type feature
3. Read and modify the 3 files listed above per the spec
4. Test by creating a test commit in the worktree
5. Create PR with: gh pr create --title "feat(V8): enforce Feature-Key and Agent trailers [bd-v8-process-fixes]"

Key constraints:
- Do NOT modify canonical repos directly
- All commits must include Feature-Key: bd-v8-process-fixes
- Test the changes before pushing
```

## Related

- PR #140: Improved pre-commit recovery UX
- Beads: bd-rpaj (V8 cleanup parent)
- Audit: 2026-02-08 PR triage findings
