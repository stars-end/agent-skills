# DX Auditor Composite Action

Automated weekly meta-analysis to detect DX toil patterns and track improvements.

## Features

- ✅ **Commit analysis**: Aggregate last N commits with Feature-Key trailers
- ✅ **CI run analysis**: Collect failure rates and patterns
- ✅ **Pattern detection**: Identify recurring toil (lockfile drift, fixture config, etc.)
- ✅ **Automated reporting**: Generate markdown reports in docs/
- ✅ **Beads integration**: Optional posting to dx-audit epic
- ⚠️  **Claude API integration**: Placeholder (not yet implemented)

## Concept

Instead of manual one-time DX analysis (like bd-vi6j), run weekly automated audits:

1. **Collect data**: Last 30-60 commits + CI runs
2. **Pre-aggregate**: Group by patterns (lockfile, beads, fixtures, etc.)
3. **Claude analysis**: Send to Claude API for insight extraction
4. **Report**: Output to docs/DX_AUDIT_LOG.md
5. **Track**: Post summary to Beads epic for historical tracking

## Usage

### Basic Weekly Audit

```yaml
name: DX Audit

on:
  schedule:
    - cron: '0 0 * * 1'  # Every Monday at midnight UTC

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: stars-end/agent-skills/.github/actions/dx-auditor@main
        with:
          lookback-commits: 60
          lookback-runs: 30
          output-file: docs/DX_AUDIT_LOG.md
```

### With Beads Integration

```yaml
- uses: stars-end/agent-skills/.github/actions/dx-auditor@main
  with:
    lookback-commits: 60
    lookback-runs: 30
    output-file: docs/DX_AUDIT_LOG.md
    beads-epic: bd-audit  # Post summary to this epic
```

### Custom Lookback Period

```yaml
- uses: stars-end/agent-skills/.github/actions/dx-auditor@main
  with:
    lookback-commits: 120  # 2x normal cycle
    lookback-runs: 60
    output-file: docs/audits/audit-$(date +%Y-%m-%d).md
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `lookback-commits` | Number of recent commits to analyze | No | `60` |
| `lookback-runs` | Number of recent CI runs to analyze | No | `30` |
| `output-file` | Output file path for audit report | No | `docs/DX_AUDIT_LOG.md` |
| `beads-epic` | Beads epic to post summary to | No | `''` |

## Outputs

| Output | Description |
|--------|-------------|
| `toil-rate` | Calculated toil rate (e.g., 0.58 for 58%) |
| `top-pattern` | Most common toil pattern detected |
| `report-path` | Path to generated audit report |

## What It Analyzes

### Commit Patterns
- **Lockfile drift**: Commits with "poetry.lock", "pnpm-lock.yaml" in message
- **Beads sync**: Commits with ".beads/issues.jsonl" in message
- **Fixture config**: Commits with "fixture", "conftest" in message
- **Python version**: Commits with "python version", "3.11" in message
- **CI iterations**: Multiple commits on same Feature-Key (toil indicator)

### CI Run Patterns
- **Failure rate**: % of CI runs that failed
- **Time to green**: Average commits per successful CI
- **Flaky tests**: Tests that fail intermittently
- **Deployment failures**: Railway/production deploy issues

### DX Metrics Tracked
- Toil rate: % of commits that are toil (not feature work)
- Time waste: Estimated hours lost to toil per month
- Top patterns: Which patterns cause most toil
- Trends: Is toil increasing or decreasing?

## Generated Report Format

```markdown
# DX Audit Report

**Generated**: 2025-12-08 00:00:00 UTC
**Commits analyzed**: 60
**CI runs analyzed**: 30

## Summary

- **Toil rate**: 0.42 (42%)
- **Top pattern**: lockfile-drift
- **CI failure rate**: 15%

## Recommendations

1. Lockfile drift (9 commits): Enable lockfile-validation.yml workflow
2. Beads sync (5 commits): Add bd-doctor to pre-push hook
3. Fixture config (8 commits): Centralize fixtures in conftest.py

## Trends

Compared to last audit (30 days ago):
- Toil rate: 58% → 42% (-16% improvement)
- Top pattern: Fixture config → Lockfile drift (shifted)
- CI failure rate: 22% → 15% (-7% improvement)

## Data

[Detailed commit-by-commit analysis]
```

## Integration Example

```yaml
name: Weekly DX Audit

on:
  schedule:
    - cron: '0 0 * * 1'  # Monday midnight
  workflow_dispatch:  # Manual trigger

jobs:
  audit:
    runs-on: ubuntu-latest
    permissions:
      contents: write  # To commit report
      issues: write    # To post to Beads epic
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 100  # Need history for analysis

      - name: Install Beads CLI (optional)
        run: |
          # Install bd CLI if posting to Beads
          pip install beads-cli

      - uses: stars-end/agent-skills/.github/actions/dx-auditor@main
        with:
          lookback-commits: 60
          lookback-runs: 30
          output-file: docs/DX_AUDIT_LOG.md
          beads-epic: bd-audit
        env:
          GH_TOKEN: ${{ github.token }}

      - name: Commit audit report
        run: |
          git config user.name "DX Auditor"
          git config user.email "dx-auditor@agent-skills"
          git add docs/DX_AUDIT_LOG.md
          git commit -m "docs: Weekly DX audit report" || echo "No changes"
          git push
```

## Why This Matters

### Manual Analysis (What We Did for bd-vi6j)
- ✅ Deep insights (6 hours of analysis)
- ❌ One-time snapshot
- ❌ Doesn't catch regressions
- ❌ Labor-intensive

### Automated Audit (This Action)
- ✅ Weekly rolling analysis
- ✅ Catches regressions early
- ✅ Tracks improvement trends
- ✅ Zero manual effort
- ⚠️  Shallower insights (but consistent)

**Best practice**: Manual deep-dive when starting DX improvements, then automated audits to monitor.

## Current Limitations

### Not Yet Implemented (Future Work)
1. **Claude API integration**: Currently placeholder - needs API key and prompt engineering
2. **Smart pattern detection**: Hardcoded patterns - could use ML
3. **Root cause analysis**: Shows symptoms, not causes
4. **Actionable recommendations**: Generic advice - could be repo-specific

### To Add Claude API
Replace the "Run Claude analysis" step with:
```yaml
- name: Run Claude analysis
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: |
    # Send aggregation to Claude API
    # Parse response for toil rate + recommendations
```

## Troubleshooting

### "GH_TOKEN: not found"

Ensure workflow has `contents: read` permission:
```yaml
permissions:
  contents: read
```

### Audit report shows 0% toil

Check:
1. Are commits using Feature-Key trailers?
2. Is lookback period too short? (increase to 120 commits)
3. Are failure patterns correctly detected?

### Beads post fails

Ensure bd CLI is installed before this action:
```yaml
- name: Install Beads
  run: pip install beads-cli
```

## Related

- **Manual DX analysis**: `docs/beads/bd-vi6j-commit-log.md` (one-time deep dive)
- **Beads epic tracking**: Create `bd-audit` epic for historical audit posts
- **Weekly workflow**: Schedule with GitHub Actions cron

## Future Enhancements

1. **Trend visualization**: Generate charts (toil rate over time)
2. **Slack/Discord integration**: Post audit summaries to team chat
3. **Comparison mode**: Compare repos (prime-radiant-ai vs affordabot)
4. **Predictive mode**: Forecast toil rate based on current trajectory
5. **Claude API integration**: Full automated analysis with recommendations
