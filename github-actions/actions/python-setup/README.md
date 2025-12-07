# Python Setup Composite Action

Auto-detect Python version from `pyproject.toml`, install Poetry, and cache dependencies.

## Features

- ✅ **Auto-version detection**: Reads Python version from `pyproject.toml` (single source of truth)
- ✅ **Poetry setup**: Installs and configures Poetry with virtualenv in project
- ✅ **Dependency caching**: Caches Poetry dependencies for faster CI runs
- ✅ **Override support**: Optionally specify Python version explicitly

## Usage

### Basic (Auto-detect from pyproject.toml)

```yaml
- uses: stars-end/agent-skills/.github/actions/python-setup@main
  with:
    working-directory: backend/
```

### With Explicit Python Version

```yaml
- uses: stars-end/agent-skills/.github/actions/python-setup@main
  with:
    working-directory: backend/
    python-version: '3.11'
```

### Using Outputs

```yaml
- uses: stars-end/agent-skills/.github/actions/python-setup@main
  id: python-setup
  with:
    working-directory: backend/

- name: Show Python version
  run: echo "Using Python ${{ steps.python-setup.outputs.python-version }}"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `working-directory` | Directory containing pyproject.toml | No | `.` |
| `python-version` | Python version override | No | Auto-detected |

## Outputs

| Output | Description |
|--------|-------------|
| `python-version` | Python version that was installed |
| `cache-hit` | Whether Poetry cache was hit |

## What It Replaces

**Before** (30+ lines per job):
```yaml
- uses: actions/setup-python@v5
  with:
    python-version: '3.11'  # Hardcoded, drifts from pyproject.toml
- name: Install Poetry
  run: curl -sSL https://install.python-poetry.org | python3 -
- name: Cache dependencies
  uses: actions/cache@v4
  with:
    path: ~/.cache/pypoetry
    key: poetry-${{ runner.os }}-...
- name: Install deps
  run: poetry install
```

**After** (3 lines):
```yaml
- uses: stars-end/agent-skills/.github/actions/python-setup@main
  with:
    working-directory: backend/
```

## Cache Strategy

Caches both:
1. `~/.cache/pypoetry` - Poetry's global cache
2. `.venv/` - Project virtualenv (if using `virtualenvs.in-project`)

Cache key: `poetry-{os}-{python-version}-{poetry.lock-hash}`

## Requirements

- `pyproject.toml` with `python = "^X.Y"` line
- `poetry.lock` for cache key generation

## Integration Example

```yaml
name: Python Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: stars-end/agent-skills/.github/actions/python-setup@main
        with:
          working-directory: backend/

      - name: Run tests
        working-directory: backend/
        run: poetry run pytest
```

## Troubleshooting

### "python = ..." not found in pyproject.toml

Ensure your `pyproject.toml` has:
```toml
[tool.poetry.dependencies]
python = "^3.11"
```

### Cache not restoring

Check that `poetry.lock` exists and is committed.

## Related Actions

- [lockfile-check](../lockfile-check/) - Validate Poetry lockfile is in sync
- [beads-preflight](../beads-preflight/) - Beads workflow checks
