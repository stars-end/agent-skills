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

### Cron / automation (cached OP resolution)

The cron wrapper uses cached 1Password resolution (`dx_auth_load_zai_api_key`) so it does not hit `op read` on every invocation.

```bash
# 3 AM UTC daily
0 3 * * * /path/to/agent-skills/scripts/enrichment/enrichment-cron-wrapper.sh >> /tmp/enrichment.log 2>&1

# Dry run via wrapper
scripts/enrichment/enrichment-cron-wrapper.sh --dry-run
```

### Interactive (manual)

```bash
# One-shot with cached resolution
source scripts/lib/dx-auth.sh && dx_auth_load_zai_api_key
python3 scripts/enrichment/nightly-enrichment.py

# Single repo
python3 scripts/enrichment/nightly-enrichment.py --repo ~/agent-skills

# Custom batch size and model
ENRICHMENT_BATCH=15 ZAI_MODEL=glm-5 \
  python3 scripts/enrichment/nightly-enrichment.py

# Custom artifact root
python3 scripts/enrichment/nightly-enrichment.py --artifact-root /tmp/enrichment-out
```

## Environment Variables

| Var | Default | Description |
|-----|---------|-------------|
| `ZAI_API_KEY` | (required) | z.ai API key (resolved via cached OP helper) |
| `ZAI_MODEL` | `glm-4.7` | z.ai model for labeling |
| `ENRICHMENT_BATCH` | `20` | Files per cluster |
| `ENRICHMENT_TIMEOUT` | `30` | Per-call timeout (seconds) |
| `ENRICHMENT_ARTIFACT_ROOT` | `~/.dx-state/enrichment/` | Override artifact output root |

### Secret Resolution

`ZAI_API_KEY` is sourced from `op://dev/Agent-Secrets-Production/ZAI_API_KEY` via the cached helper in `scripts/lib/dx-auth.sh`. The wrapper calls `dx_auth_load_zai_api_key` which:
1. Checks if `ZAI_API_KEY` is already exported and not an `op://` reference — returns immediately
2. Reads from the local secret cache (`~/.cache/dx/op-secrets/`, 24h TTL)
3. On cache miss, refreshes via `op item get` using the service account token
4. Exports `ZAI_API_KEY` for the Python script

No raw `op read` is needed in cron or automation. See `core/op-secrets-quickref/SKILL.md` for the full cached-secret contract.

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
