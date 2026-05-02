# semantic-search

`semantic-search` is an optional warmed semantic-hints wrapper over `ccc`.

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

`ready` requires valid schema v1 metadata (`state.json`), index DB + settings,
healthy bounded `ccc status`, canonical HEAD match with `indexed_head`, and a
clean worktree relationship policy.

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
