# Nightly z.ai Enrichment Job

Generates semantic enrichment artifacts for context-plus from existing embedding caches.

## What It Does

Reads `.mcp_data/embeddings-cache.json` from each tracked repo (read-only) and produces:
- `cluster-labels.json` - 2-3 word labels for file clusters
- `file-summaries.json` - 5-10 word per-file descriptions
- `semantic-descriptions.json` - One-sentence descriptions for agent context

## Artifact Location

Artifacts are written to an **external state root**, not into canonical repo clones.

Default: `~/.dx-state/enrichment/{repo-name}/`

```
~/.dx-state/enrichment/
  agent-skills/
    cluster-labels.json
    file-summaries.json
    semantic-descriptions.json
  prime-radiant-ai/
    ...
```

Override via `ENRICHMENT_ARTIFACT_ROOT` env var or `--artifact-root` flag.

## Invocation

```bash
# Full run against all canonical repos
ZAI_API_KEY=$(op read 'op://dev/Agent-Secrets-Production/ZAI_API_KEY') \
  python3 scripts/enrichment/nightly-enrichment.py

# Dry run (no z.ai calls)
python3 scripts/enrichment/nightly-enrichment.py --dry-run

# Single repo
python3 scripts/enrichment/nightly-enrichment.py --repo ~/agent-skills

# Custom batch size and model
ENRICHMENT_BATCH=15 ZAI_MODEL=glm-5 \
  python3 scripts/enrichment/nightly-enrichment.py

# Custom artifact root
python3 scripts/enrichment/nightly-enrichment.py --artifact-root /tmp/enrichment-out
```

## Cron Installation

```bash
# 3 AM UTC daily
0 3 * * * ZAI_API_KEY=$(op read 'op://dev/Agent-Secrets-Production/ZAI_API_KEY') /path/to/python3 /path/to/agent-skills/scripts/enrichment/nightly-enrichment.py >> /tmp/enrichment.log 2>&1
```

## Environment Variables

| Var | Default | Description |
|-----|---------|-------------|
| `ZAI_API_KEY` | (required) | z.ai API key |
| `ZAI_MODEL` | `glm-4.7` | z.ai model for labeling |
| `ENRICHMENT_BATCH` | `20` | Files per cluster |
| `ENRICHMENT_TIMEOUT` | `30` | Per-call timeout (seconds) |
| `ENRICHMENT_ARTIFACT_ROOT` | `~/.dx-state/enrichment/` | Override artifact output root |

## Dependencies

- Python 3.11+
- llm-common (`pip install llm-common`) - provides `ZaiClient` for z.ai API access

## Volume Estimate

~20-100 z.ai API calls per night across 4 repos (free tier).

## Output

Per repo in `{artifact_root}/{repo-name}/`:
```
{artifact_root}/{repo-name}/
  cluster-labels.json      # [{cluster_index, label, theme, files}]
  file-summaries.json      # [{path, summary}]
  semantic-descriptions.json # [{path, description}]
```
