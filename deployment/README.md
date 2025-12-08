# Deployment Tooling

Scripts to help sync agent-skills templates to target repos.

## 🛠️ Available Scripts

### check-drift.sh
Check if a repo's workflows have drifted from agent-skills reference templates.

**Usage**:
```bash
~/.agent/skills/deployment/check-drift.sh ~/prime-radiant-ai
```

**Output**:
```
✅ lockfile-validation.yml - in sync
❌ python-test-job.yml - DRIFT DETECTED
⚠️  dx-auditor.yml - not deployed

⚠️  1 workflow(s) have drift

To sync:
  ~/.agent/skills/deployment/sync-to-repo.sh ~/prime-radiant-ai
```

**Exit codes**:
- `0` - All workflows in sync
- `1` - Drift detected or errors

---

### sync-to-repo.sh
Sync agent-skills workflow templates to a target repo.

**Usage**:
```bash
~/.agent/skills/deployment/sync-to-repo.sh ~/prime-radiant-ai
```

**Interactive prompts**:
```
Available templates:
  - lockfile-validation.yml
  - python-test-job.yml
  - dx-auditor.yml

Select templates to sync (comma-separated, or 'all'): all

⚠️  python-test-job.yml already exists in target repo

Diff:
[shows diff between reference and target]

Overwrite? (y/N): y

✅ Synced 3 template(s) to ~/prime-radiant-ai

Next steps:
  cd ~/prime-radiant-ai
  git status
  git add .github/workflows/
  git commit -m 'ci: Sync workflow templates from agent-skills'
```

**Selective sync**:
```bash
# Sync only specific templates
Select templates to sync: lockfile-validation.yml, dx-auditor.yml
```

## 📋 Workflow

### Initial Deployment (New Repo)
```bash
# 1. Sync templates to repo
~/.agent/skills/deployment/sync-to-repo.sh ~/new-repo

# 2. Review and commit
cd ~/new-repo
git status
git diff .github/workflows/
git add .github/workflows/
git commit -m "ci: Add agent-skills workflow templates"
git push
```

### Periodic Drift Checks (Existing Repo)
```bash
# 1. Update agent-skills
cd ~/.agent/skills
git pull

# 2. Check for drift
~/.agent/skills/deployment/check-drift.sh ~/your-repo

# 3. If drift detected, review diff
diff ~/.agent/skills/github-actions/workflows/lockfile-validation.yml.ref \
     ~/your-repo/.github/workflows/lockfile-validation.yml

# 4. Sync if desired
~/.agent/skills/deployment/sync-to-repo.sh ~/your-repo
```

### Automated Drift Detection (Optional)
Add to your repo's CI:

```yaml
name: Check Template Drift

on:
  schedule:
    - cron: '0 0 * * 1'  # Weekly
  workflow_dispatch:

jobs:
  check-drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Update agent-skills
        run: |
          git clone https://github.com/stars-end/agent-skills ~/.agent/skills
          # Or: cd ~/.agent/skills && git pull

      - name: Check drift
        run: ~/.agent/skills/deployment/check-drift.sh .

      - name: Create issue if drift
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: 'Workflow templates have drifted from agent-skills',
              body: 'Run `~/.agent/skills/deployment/sync-to-repo.sh .` to sync'
            })
```

## 🎯 Philosophy

**Manual, agent-initiated sync** - Not automatic

**Why**:
- ✅ Agents control when to update (avoid surprise breakages)
- ✅ Review diffs before syncing (understand changes)
- ✅ No brittle automation (no auto-commits, no auto-PRs)

**When to sync**:
- After `git pull` in agent-skills shows workflow changes
- Monthly drift checks (via check-drift.sh)
- When starting new repos (sync all templates)

## 📊 Template Sync Frequency

| Frequency | Use Case |
|-----------|----------|
| **On-demand** | Agent notices improvements, runs sync |
| **Weekly** | Automated drift detection in CI (issue created) |
| **Monthly** | Manual audit of all repos |

## 🐛 Troubleshooting

### "agent-skills not found"
```bash
cd ~/.agent/skills && git pull
# Or clone: git clone https://github.com/stars-end/agent-skills ~/.agent/skills
```

### "Target repo not found"
Ensure you provide absolute path:
```bash
~/.agent/skills/deployment/sync-to-repo.sh ~/prime-radiant-ai
# Not: ./prime-radiant-ai
```

### Sync creates conflicts
If templates have significant customization, consider:
1. Manual merge (copy sections, not whole file)
2. Fork template pattern (maintain custom version)
3. Update composite actions only (skip workflow sync)

### Want to test sync without committing
```bash
# Dry run - copy to temp location first
cp -r ~/your-repo /tmp/repo-backup
~/.agent/skills/deployment/sync-to-repo.sh /tmp/repo-backup
# Review changes, then apply to real repo if satisfied
```

## 📚 Related

- **Workflow templates**: `../github-actions/workflows/` - Reference implementations
- **Composite actions**: `../github-actions/actions/` - Reusable actions (no sync needed)
- **check-drift CI**: Example workflow above for automated monitoring

## 🔮 Future Enhancements

1. **--dry-run mode**: Show what would sync without making changes
2. **--force mode**: Skip interactive prompts for CI usage
3. **Diff viewer**: Better visual diff before overwriting
4. **Repo-specific configs**: `.agent-skills-sync.json` to exclude certain templates
5. **Batch sync**: Sync to multiple repos at once
