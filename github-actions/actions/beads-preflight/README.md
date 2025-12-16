# Beads Preflight Composite Action

Validate Beads workflow health in CI before expensive operations run.

## Features

- ✅ **JSONL checks**: Detect unstaged .beads/issues.jsonl changes
- ✅ **Feature-Key validation**: Ensure commits have proper trailers
- ✅ **Branch/issue alignment**: Verify feature-bd-xyz branch matches open issue bd-xyz
- ✅ **Optional enforcement**: Warning-only mode (default) or fail CI
- ✅ **Graceful skip**: Auto-skips if bd CLI not available (works in non-Beads repos)

## Usage

### Warning-Only Mode (Recommended for CI)

```yaml
- uses: stars-end/agent-skills/.github/actions/beads-preflight@main
```

This will:
- ✅ Run checks
- ⚠️  Show warnings if issues found
- ✅ Continue CI (does not fail)

### Strict Mode (Fail on Issues)

```yaml
- uses: stars-end/agent-skills/.github/actions/beads-preflight@main
  with:
    fail-on-issues: true
```

This will:
- ✅ Run checks
- ❌ Fail CI if issues detected
- Use for protected workflows where Beads sync is critical

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `check-only` | Only check, no auto-fix (CI read-only) | No | `true` |
| `fail-on-issues` | Fail CI if issues detected | No | `false` |

## Outputs

| Output | Description | Values |
|--------|-------------|--------|
| `status` | Beads health status | `ok`, `warning`, `error`, `skipped` |
| `issues-found` | Comma-separated list of issues | e.g., `unstaged-jsonl,missing-feature-key` |

## What It Checks

### 1. Unstaged JSONL Changes
**Problem**: .beads/issues.jsonl modified but not committed
**Detection**: `git status --porcelain | grep .beads/issues.jsonl`
**Fix**: Run `bd-doctor/fix.sh` or `git add .beads/issues.jsonl`

### 2. Missing Feature-Key Trailer
**Problem**: Commit on feature branch lacks `Feature-Key: bd-xyz` trailer
**Detection**: `git log -1 --format=%B | grep "Feature-Key:"`
**Fix**: Amend commit with Feature-Key or use sync-feature-branch skill

### 3. Branch/Issue Alignment
**Problem**: On `feature-bd-xyz` but issue `bd-xyz` is not open
**Detection**: Check bd list for matching issue ID
**Fix**: Reopen issue or switch branches

## Integration Example

```yaml
name: CI

on: [push, pull_request]

jobs:
  preflight:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Install bd CLI (if using Beads)
      - name: Install Beads
        run: |
          # Add your bd CLI installation here
          # e.g., pip install beads-cli

      - uses: stars-end/agent-skills/.github/actions/beads-preflight@main
        with:
          fail-on-issues: false  # Warning-only

  tests:
    needs: preflight
    runs-on: ubuntu-latest
    steps:
      # ... your test jobs
```

## What It Prevents

**Pattern 3: Beads Sync Issues** (7/69 toil commits eliminated)
- ❌ Before: Beads sync fails in pre-push hook → Manual fix → Retry
- ✅ After: CI detects sync issues early with clear guidance

## When to Use

### Use in CI when:
- ✅ Working on Beads-tracked feature branches
- ✅ Want early detection of sync issues
- ✅ Using Beads CLI in your workflow

### Skip when:
- ⚠️  Repository doesn't use Beads
- ⚠️  Working on non-feature branches (master, hotfix)
- ⚠️  bd CLI not available (action auto-skips)

## Local Alternative

For local checks before pushing:
```bash
~/.agent/skills/bd-doctor/check.sh
~/.agent/skills/bd-doctor/fix.sh  # Auto-fix if needed
```

## Troubleshooting

### "bd: command not found"

Action will auto-skip with warning. If you want Beads checks:
1. Install bd CLI in CI (before this action)
2. Or remove beads-preflight from workflow (not needed)

### Checks pass locally but fail in CI

Ensure `.beads/issues.jsonl` is committed:
```bash
git status .beads/
git add .beads/issues.jsonl
git commit --amend --no-edit
```

### False positive on master branch

Beads-preflight only checks feature branches. If running on master and getting warnings, this is expected behavior for sync operations.

## Related

- **Local skill**: `~/.agent/skills/bd-doctor/` - Same checks with auto-fix
- **Beads CLI**: https://github.com/steveyegge/beads
- **sync-feature-branch skill**: Proper commit workflow with Beads metadata
