---
name: beads-spec-write
description: |
  Repairs Beads issues to satisfy bd lint requirements. Ensures required headings exist in issue description based on type. Use when agent says "fix bd lint", "repair spec", or "update issue for compliance".
tags: [beads, lint, spec, documentation, workflow]
allowed-tools:
  - Bash(bd:*)
  - Read
  - mcp__plugin_beads_beads__*
---

# Beads Spec-Write Skill

**Purpose:** Ensures Beads issues pass `bd lint` by adding required headings based on issue type.

## Activation

**Triggers:**
- "fix bd lint for bd-xyz"
- "repair spec for bd-xyz"
- "make issue bd-xyz compliant"
- "update issue to pass lint"

**User provides:** Beads issue ID (bd-xyz)

## Core Workflow

### Required Headings by Type

The skill checks the issue type and ensures these headings exist in `description`:

| Issue Type | Required Headings |
|------------|------------------|
| `epic` | `## Success Criteria` |
| `feature` | `## Acceptance Criteria` |
| `task` | `## Acceptance Criteria` |
| `bug` | `## Steps to Reproduce` + `## Acceptance Criteria` |

### Recommended (but not required by lint)

- `## Verification` - Evidence of what was run/tested

### Behavior

1. Read issue via `bd show <id> --json`
2. Check current `description` for required headings based on type
3. If any required heading is missing, append a template
4. If `## Verification` is missing, append a template (optional)
5. Update the issue
6. Run `bd lint <id>` to verify
7. Report PASS/FAIL with missing headings (if any)

### Idempotency

The skill is idempotent: running it twice will not duplicate headings. It checks for existing headings before appending.

## Workflow

### 1. Run the Skill

```bash
cd ~/agent-skills-worktrees/bd-umrk
bd-show bd-xyz | grep "type:" # Check type
./extended/beads-spec-write/run.sh bd-xyz
```

### 2. Verify Compliance

```bash
bd lint bd-xyz
```

### 3. Review Changes

```bash
bd show bd-xyz
```

## Usage Examples

### Example 1: Repair Epic

```bash
# Issue bd-umrk is an epic but missing "Success Criteria"
./extended/beads-spec-write/run.sh bd-umrk
```

Output:
```
✓ Issue bd-umrk is an epic
✓ Missing required heading: ## Success Criteria
✓ Appending template for Success Criteria
✓ Checking for recommended heading: ## Verification
✓ Appending template for Verification
✓ Updated issue bd-umrk
Running bd lint...
✓ PASS: bd-umrk
```

### Example 2: Repair Bug

```bash
# Issue bd-abc is a bug missing required headings
./extended/beads-spec-write/run.sh bd-abc
```

Output:
```
✓ Issue bd-abc is a bug
✓ Missing required heading: ## Steps to Reproduce
✓ Appending template for Steps to Reproduce
✓ Missing required heading: ## Acceptance Criteria
✓ Appending template for Acceptance Criteria
✓ Checking for recommended heading: ## Verification
✓ Appending template for Verification
✓ Updated issue bd-abc
Running bd lint...
✓ PASS: bd-abc
```

### Example 3: Already Compliant

```bash
# Issue bd-xyz already has all required headings
./extended/beads-spec-write/run.sh bd-xyz
```

Output:
```
✓ Issue bd-xyz is a feature
✓ Required heading: ## Acceptance Criteria exists
✓ Recommended heading: ## Verification exists
Running bd lint...
✓ PASS: bd-xyz
```

## Template Contents

### Epic: Success Criteria

```markdown
## Success Criteria

- [ ] Criterion 1
- [ ] Criterion 2
```

### Feature/Task: Acceptance Criteria

```markdown
## Acceptance Criteria

- [ ] AC 1: <description>
- [ ] AC 2: <description>
```

### Bug: Steps to Reproduce

```markdown
## Steps to Reproduce

1. Step 1
2. Step 2
3. Step 3
```

### Bug: Acceptance Criteria

```markdown
## Acceptance Criteria

- [ ] The bug is fixed and no longer occurs
- [ ] No regressions introduced
```

### All Types: Verification (recommended)

```markdown
## Verification

What was run to verify this work:
- [ ] Test X passed
- [ ] Test Y passed
- [ ] Manual verification of Z

Evidence:
- <link to logs/screenshots or paste output>
```

## Implementation Notes

The skill uses `BEADS_DIR` environment variable to point to the shared Beads database in `~/bd/.beads`.

The skill does not create any files in product repos - it only updates Beads issues in the central database.

## Troubleshooting

### "Issue not found"

Verify the Beads ID is correct and the issue exists:

```bash
bd show bd-xyz
```

### "bd lint still fails"

After running the skill, check the lint output:

```bash
bd lint bd-xyz --verbose
```

The skill may have added the headings but the content needs to be filled in.

### "Permission denied"

Ensure you have write access to the Beads database and `BEADS_DIR` is set:

```bash
echo $BEADS_DIR
# Should output: /Users/fengning/bd/.beads
```

## Version History

- **v1.0.0** (2026-02-05): Initial implementation for bd-umrk.1
  - Supports epic, feature, task, bug types
  - Ensures required headings for `bd lint`
  - Idempotent (no duplicate headings)
