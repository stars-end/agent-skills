# Lockfile Check Composite Action

Fast-fail CI validation that Poetry and pnpm lockfiles are in sync with manifests.

## Features

- ✅ **Poetry validation**: `poetry check --lock` for backend
- ✅ **pnpm validation**: `--frozen-lockfile` check for frontend
- ✅ **Selective checking**: Skip backend or frontend if not present
- ✅ **Clear error messages**: Shows exact commands to fix drift
- ✅ **Fast feedback**: Fails in <2 min before expensive test suites run

## Usage

### Both Backend + Frontend

```yaml
- uses: stars-end/agent-skills/.github/actions/lockfile-check@main
  with:
    backend-directory: backend/
    frontend-directory: frontend/
```

### Backend Only

```yaml
- uses: stars-end/agent-skills/.github/actions/lockfile-check@main
  with:
    backend-directory: backend/
    frontend-directory: ''  # Skip frontend
```

### Root-Level Directories

```yaml
- uses: stars-end/agent-skills/.github/actions/lockfile-check@main
  with:
    backend-directory: .  # pyproject.toml in repo root
    frontend-directory: ''
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `backend-directory` | Directory with pyproject.toml (empty to skip) | No | `backend` |
| `frontend-directory` | Directory with package.json (empty to skip) | No | `frontend` |
| `fail-fast` | Fail on first error or check all | No | `true` |

## Outputs

| Output | Description | Values |
|--------|-------------|--------|
| `poetry-status` | Poetry lockfile status | `ok`, `drift`, `missing`, `skipped` |
| `pnpm-status` | pnpm lockfile status | `ok`, `drift`, `missing`, `skipped` |

## Error Messages

When lockfile drift is detected, CI shows:

```
❌ Poetry lockfile is OUT OF SYNC with pyproject.toml

To fix locally:
  cd backend/
  poetry lock --no-update
  git add poetry.lock

Or use lockfile-doctor skill:
  ~/.agent/skills/lockfile-doctor/fix.sh
```

## Integration Example

```yaml
name: Lockfile Validation

on:
  pull_request:
    paths:
      - 'backend/pyproject.toml'
      - 'backend/poetry.lock'
      - 'frontend/package.json'
      - 'frontend/pnpm-lock.yaml'

jobs:
  validate-lockfiles:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4

      - name: Set up Poetry
        run: pip install poetry

      - name: Set up pnpm
        uses: pnpm/action-setup@v2
        with:
          version: 8

      - uses: stars-end/agent-skills/.github/actions/lockfile-check@main
```

## What It Prevents

**Pattern 1: Lockfile Drift** (9/69 toil commits eliminated)
- ❌ Before: Add dependency → Forget lockfile → CI fails at test stage (5-10 min wasted)
- ✅ After: Lockfile check fails in <2 min with clear fix instructions

**Impact**: Fast feedback loop, prevents wasted CI time on expensive tests.

## Related

- **Local skill**: `~/.agent/skills/lockfile-doctor/` - Same checks, auto-fix capability
- **Workflow template**: `github-actions/workflows/lockfile-validation.yml.ref` - Full CI workflow

## Troubleshooting

### "poetry: command not found"

Add Poetry setup before this action:
```yaml
- name: Install Poetry
  run: pip install poetry
```

### "pnpm: command not found"

Add pnpm setup:
```yaml
- uses: pnpm/action-setup@v2
  with:
    version: 8
```

### Check passes locally but fails in CI

Ensure lockfile is committed:
```bash
git status  # Check if poetry.lock or pnpm-lock.yaml is unstaged
git add backend/poetry.lock frontend/pnpm-lock.yaml
```
