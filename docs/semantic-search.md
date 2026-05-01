# semantic-search wrapper

`semantic-search` is a thin wrapper around `ccc` for optional semantic hints.
It is not default truth and never builds or updates indexes.

## Commands

```bash
scripts/semantic-search status --repo /path/to/repo
scripts/semantic-search query --repo /path/to/repo "natural language query" --limit 10
```

Status returns exactly one value:

- `missing`: `.cocoindex_code/settings.yml` or `.cocoindex_code/target_sqlite.db` absent
- `indexing`: bounded `ccc status` indicates indexing in progress (or times out)
- `stale`: index exists but repo appears ahead (dirty tree or newer git ref/index mtime)
- `ready`: index exists, not indexing, and not stale

## Query behavior

- `query` runs bounded `ccc status` first.
- `query` runs bounded `ccc search` only when status is `ready`.
- For `missing`, `indexing`, or `stale`, it exits nonzero and prints:
  `semantic index unavailable; use rg.`

This preserves `rg` as the default critical-path route while allowing optional,
warm semantic enrichment when an external index is already ready.

## Optional env override

- `SEMANTIC_SEARCH_CCC_BIN`: path to `ccc` binary for testing or custom installs.
