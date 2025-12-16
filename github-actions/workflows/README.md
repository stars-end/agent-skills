# GitHub Actions Workflow Templates

Reference implementations for common CI/CD workflows. Copy and adapt for your repo.

## 📁 Available Templates

| Template | Purpose | Copy to Repo |
|----------|---------|--------------|
| `lockfile-validation.yml.ref` | Fast-fail lockfile checks | `.github/workflows/lockfile-validation.yml` |
| `python-test-job.yml.ref` | Python tests with auto-setup | `.github/workflows/tests.yml` |
| `dx-auditor.yml.ref` | Weekly DX meta-analysis | `.github/workflows/dx-audit.yml` |
| `auto-merge-beads.yml.ref` | Auto-resolve Beads JSONL conflicts | `.github/workflows/auto-merge-beads.yml` |

## 🎯 Why Templates, Not Reusable Workflows?

**GitHub limitation**: Workflows cannot reference other repos' workflows directly.

**Solution**:
- **Composite actions** (80% of logic): Referenceable across repos via `uses: stars-end/agent-skills/.github/actions/...@main`
- **Workflow templates** (20% orchestration): Copy-on-deploy, adapt paths/triggers

## 🚀 Quick Start

### 1. Copy Template to Your Repo

```bash
# Example: Add lockfile validation
cp ~/.agent/skills/github-actions/workflows/lockfile-validation.yml.ref \
   ~/your-repo/.github/workflows/lockfile-validation.yml
```

### 2. Adapt for Your Repo Structure

**If backend/ and frontend/ directories**:
```yaml
# No changes needed - defaults work
- uses: stars-end/agent-skills/.github/actions/lockfile-check@main
```

**If different directory structure**:
```yaml
# Example: Backend in root, frontend in client/
- uses: stars-end/agent-skills/.github/actions/lockfile-check@main
  with:
    backend-directory: .
    frontend-directory: client/
```

### 3. Commit and Push

```bash
git add .github/workflows/
git commit -m "ci: Add lockfile validation workflow"
git push
```

## 📖 Template Details

### lockfile-validation.yml.ref

**What it does**: Fast-fail CI check for Poetry and pnpm lockfile drift

**Triggers**:
- PRs touching manifests or lockfiles
- Pushes to master/main

**Adapts to**:
- Root-level pyproject.toml: Set `backend-directory: .`
- No frontend: Set `frontend-directory: ''`
- Different pnpm version: Update `pnpm/action-setup` version

**Reference**: [lockfile-check action](../actions/lockfile-check/README.md)

---

### python-test-job.yml.ref

**What it does**: Python test job with auto-version detection and Poetry setup

**Triggers**: All pushes and PRs

**Adapts to**:
- Different test directory: Change `poetry run pytest tests/` to your path
- Additional test commands: Add steps after pytest
- Code coverage: Uncomment codecov upload step

**Reference**: [python-setup action](../actions/python-setup/README.md)

---

### dx-auditor.yml.ref

**What it does**: Weekly automated DX meta-analysis

**Triggers**:
- Scheduled: Every Monday midnight UTC
- Manual: workflow_dispatch button

**Adapts to**:
- Different lookback period: Change `lookback-commits` and `lookback-runs`
- Different schedule: Update cron expression
- Beads integration: Uncomment `beads-epic` and CLI install

**Reference**: [dx-auditor action](../actions/dx-auditor/README.md)

## 🔄 Keeping Templates Updated

When agent-skills updates:

1. **Composite actions auto-update**: Your workflows automatically use latest via `@main`
2. **Workflow templates**: Manual sync needed (copy new template over)

**Check for updates**:
```bash
cd ~/.agent/skills
git pull
diff github-actions/workflows/lockfile-validation.yml.ref \
     ~/your-repo/.github/workflows/lockfile-validation.yml
```

**Deployment tooling** (coming soon):
```bash
~/.agent/skills/deployment/check-drift.sh  # Check for template changes
~/.agent/skills/deployment/sync-to-repo.sh  # Sync templates to repo
```

## 🎨 Customization Examples

### Example 1: Lockfile Check with Custom Paths

```yaml
# Your repo: backend in server/, no frontend
- uses: stars-end/agent-skills/.github/actions/lockfile-check@main
  with:
    backend-directory: server/
    frontend-directory: ''  # Skip frontend check
```

### Example 2: Python Tests with Multiple Directories

```yaml
jobs:
  test-api:
    steps:
      - uses: stars-end/agent-skills/.github/actions/python-setup@main
        with:
          working-directory: api/
      - run: cd api && poetry run pytest

  test-worker:
    steps:
      - uses: stars-end/agent-skills/.github/actions/python-setup@main
        with:
          working-directory: worker/
      - run: cd worker && poetry run pytest
```

### Example 3: DX Audit with Beads Integration

```yaml
- name: Install Beads CLI
  run: pip install beads-cli

- uses: stars-end/agent-skills/.github/actions/dx-auditor@main
  with:
    lookback-commits: 120  # 2x normal cycle
    lookback-runs: 60
    beads-epic: bd-audit  # Post summary to epic
```

## 📊 Composite Actions Reference

All templates use these reusable actions:

| Action | Purpose | Docs |
|--------|---------|------|
| `python-setup` | Auto-detect Python + Poetry setup | [README](../actions/python-setup/README.md) |
| `lockfile-check` | Validate lockfile sync | [README](../actions/lockfile-check/README.md) |
| `beads-preflight` | Beads health checks | [README](../actions/beads-preflight/README.md) |
| `railway-preflight` | Railway pre-deployment checks | [README](../actions/railway-preflight/README.md) |
| `dx-auditor` | Automated DX meta-analysis | [README](../actions/dx-auditor/README.md) |

## 🐛 Troubleshooting

### Template doesn't match my repo structure

Templates assume:
- Backend: `backend/` with pyproject.toml
- Frontend: `frontend/` with package.json

If different, update `with:` parameters in workflow.

### Composite action not found

Ensure you're referencing the correct path:
```yaml
uses: stars-end/agent-skills/.github/actions/python-setup@main
#     ^^^^^^^^^^^^^^^^^^^^ repo ^^^^^^^^^^^^^^^^^^^^^^ action ^^ branch
```

### Want to pin to specific version

Replace `@main` with `@<commit-sha>`:
```yaml
uses: stars-end/agent-skills/.github/actions/python-setup@b2ff2b4
```

## 📚 Related

- **Composite actions**: `../actions/` - Reusable logic (no copying needed)
- **Deployment tooling**: `../../deployment/` - Scripts to sync templates
- **bd-vi6j epic**: Original DX improvement work that created these patterns

---

**Workflow philosophy**: 80% of logic in composite actions (referenceable), 20% in workflow templates (copy-on-deploy).
