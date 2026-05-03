# Semantic Search

`semantic-search` is an optional warmed semantic-hints wrapper over `ccc`.

It is not source of truth. If the index is unavailable, agents must use `rg`
and direct reads rather than blocking on indexing.

## Status

Command:

```bash
scripts/semantic-search status --repo <worktree-or-canonical-path>
```

Output is exactly one of:

- `ready`
- `indexing`
- `missing`
- `stale`

`ready` requires valid schema v1 metadata (`state.json`), ccc DB + settings in
the non-canonical index surface, healthy bounded `ccc status`, canonical HEAD
match with `indexed_head`, and a clean worktree relationship policy.

## Query

Command:

```bash
scripts/semantic-search query --repo <worktree-or-canonical-path> "<query>" --limit <n>
```

Query runs bounded `ccc search` only when status is `ready`. It never runs
`ccc index` on the query path. Results are tagged with `indexed_head=<sha>` on
stderr so hints are anchored to the indexed canonical baseline.

For non-ready status, timeout, missing `ccc`, or unusable `ccc` results, it
prints exactly:

```text
semantic index unavailable; use rg.
```

## Refresh And Scheduling

`scripts/semantic-index-refresh` is the scheduled refresh entrypoint for `ccc`
index surfaces. It only operates on the allowlisted repositories in
`configs/semantic-index/repositories.json`:

- `agent-skills`
- `prime-radiant-ai`
- `affordabot`
- `llm-common`

Default index root:

`~/.cache/agent-semantic-indexes/<repo-name>/`

Per-repo runtime layout:

- `repo/` non-canonical index surface clone
- `coco-global/` isolated `COCOINDEX_CODE_DIR`
- `state.json` refresh metadata schema version `1`
- `refresh.log` append-only command log
- `refresh.lock` per-repo concurrency guard

`ccc` commands run from `repo/` with `COCOINDEX_CODE_DIR` pointed at
`coco-global/`. Current ccc versions store the project DB/settings in
`repo/.cocoindex_code/`; wrappers should not assume the DB lives directly under
the cache root.

Supported commands:

```bash
scripts/semantic-index-refresh --repo-name agent-skills
scripts/semantic-index-refresh --all
scripts/semantic-index-refresh --repo-name llm-common --dry-run
scripts/semantic-index-refresh --all --index-root /tmp/semantic-indexes
```

Dry-run behavior is non-mutating: it prints planned operations and does not
clone, fetch, initialize, index, write DB, or write state.

Failure behavior:

- unknown repository names fail closed and exit nonzero
- refresh failures write inspectable `state.json` with `status: failure`
- command exits nonzero for cron/systemd visibility

Daemon/process behavior:

- refresh always sets repo-scoped `COCOINDEX_CODE_DIR`
- it attempts scoped `ccc daemon stop` after each run
- on stop failure/timeout, cleanup is restricted to processes matching that
  repo's `COCOINDEX_CODE_DIR`

### Hourly Cron Wrapper

Use:

```bash
scripts/semantic-index-cron.sh
```

This wrapper runs `--all` and writes logs to:

`~/.cache/agent-semantic-indexes/logs/semantic-index-cron.log`

It is safe to invoke from cron or a systemd timer, but this repo does not
install or enable timers automatically.
