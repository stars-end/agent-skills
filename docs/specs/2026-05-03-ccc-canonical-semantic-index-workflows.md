# ccc Canonical Semantic Index Workflows

Feature-Key: bd-9n1t2.31

## Summary

Decision: `ALL_IN_NOW` for implementing CocoIndex Code (`ccc`) as an optional
warmed semantic-hints lane.

This does not make semantic search default truth. The default critical path
remains `rg`/`fd`/direct reads plus known-symbol tooling. `ccc` queries are
allowed only when an already-built canonical index is `ready`; otherwise the
agent-facing command exits quickly with:

```text
semantic index unavailable; use rg.
```

## Problem

`llm-tldr` semantic fallback is failing often enough that agents repeatedly see
`semantic_index_missing` and fall back manually. We should remove it from default
routing and provide a simpler optional semantic lane that does not block agent
lookup.

The `ccc` product is viable only if indexing is moved out of agent query time.
The implementation must separate:

- scheduled canonical index refresh
- readiness metadata
- worktree-to-canonical-index resolution
- bounded query execution

## Source Evidence

Prior local POC artifacts:

| Evidence | Result |
|---|---|
| PR #608 | Safe wrapper concept, but stale detection is too pessimistic because `.git/index` mtime can move after indexing. |
| PR #609 | Canonical index strategy: durable non-canonical index surfaces under cache, query from worktrees, never index on query. |
| PR #610 | Removes `extended/wooyun-legacy`, which dominated `agent-skills` indexing. |
| Retest on PR #610 head `ad2fcede06bb5d85391cee237ecd4b7e58df38d0` | `agent-skills` cold index finished in 407s, 832 files, 8,340 chunks, 33M DB, queries 1-2s, incremental re-index 2s. |
| `prime-radiant-ai` 60m POC | cold index 1,924s, DB 71M, 2,280 files, 24,653 chunks, warm queries 2-3s, incremental 6s. |
| earlier POC | `affordabot` and `llm-common` produced useful warmed semantic results. |

## Migration Rationale

This work intentionally replaces the default `llm-tldr` semantic route. It does
not run a second default semantic system beside `llm-tldr`.

`llm-tldr` remains available only for explicitly bounded structural/context
operations until those are separately removed or replaced. The existing
`tldr-semantic-prewarm` path must not remain part of the default agent semantic
workflow after this implementation lands. If a host still has an old
`llm-tldr` semantic cron/prewarm job, the integration task must document whether
it is disabled, left as an operator-only legacy command, or removed from
published guidance.

## Goals

- Replace failing `llm-tldr` semantic fallback with a bounded optional
  `semantic-search` lane.
- Keep cloud calls out of the default critical path; tested `ccc` configuration
  uses local SentenceTransformers embeddings.
- Make scheduled indexing boring: lock-protected, logged, bounded, and
  inspectable.
- Make agent query behavior boring: `ready | indexing | missing | stale`, no
  hidden indexing, no daemon repair loops, no founder babysitting.
- Support `dx-worktree` by resolving ephemeral task worktrees to durable
  canonical index surfaces.

## Non-Goals

- Do not make semantic search the first-hop lookup tool.
- Do not run `ccc index` from `semantic-search query`.
- Do not write `.cocoindex_code` into canonical working clones during ordinary
  agent work.
- Do not require OpenRouter or any cloud embedding provider for this lane.
- Do not preserve dual llm-tldr semantic routing in default guidance.
- Do not leave `llm-tldr` semantic prewarm as a required scheduled job for the
  default agent workflow.

## Active Contract

### Query Contract

`scripts/semantic-search query --repo <worktree-or-canonical> "<query>"`

- Resolves the repo to a configured canonical index surface.
- Reads `state.json`.
- Performs a bounded direct read against the warmed ccc SQLite index only when
  status is `ready`.
- For `missing`, `indexing`, or `stale`, exits nonzero and prints exactly:
  `semantic index unavailable; use rg.`
- Never runs raw `ccc init`, `ccc index`, `ccc status`, `ccc search`,
  `git pull`, or package/model install.

### Status Contract

`scripts/semantic-search status --repo <worktree-or-canonical>`

Returns exactly one of:

- `ready`: index DB exists, `state.json` records a successful refresh for the
  same canonical repo and indexed HEAD, and worktree/canonical HEAD policy
  matches the indexed baseline.
- `indexing`: lock or state says a refresh is in progress, or bounded
  metadata lock inspection reports indexing.
- `missing`: no configured index surface, no settings, no DB, no metadata, or
  `ccc` is unavailable.
- `stale`: index exists but metadata shows a different indexed HEAD than the
  resolved canonical branch, refresh failed, metadata is too old, or worktree
  HEAD is not an ancestor/descendant policy match.

Worktree HEAD policy:

- For canonical paths and clean freshly-created worktrees, `ready` requires the
  target HEAD to equal `state.indexed_head` or to have `state.indexed_head` as
  an ancestor.
- Dirty worktrees are `stale`. Semantic hints should be used during initial
  planning against the canonical baseline, not after substantial local edits.
- If the target HEAD is not related to `state.indexed_head`, return `stale`.
- Results printed from `query` must label the indexed HEAD so agents know the
  hints describe the last refreshed canonical baseline.

### Refresh Contract

Scheduled refresh:

- Operates only on an allowlist: `agent-skills`, `prime-radiant-ai`,
  `affordabot`, `llm-common`.
- Uses durable index roots under:
  `~/.cache/agent-semantic-indexes/<repo-name>/`.
- Uses non-canonical index clones/surfaces, not task worktrees.
- Uses per-repo `COCOINDEX_CODE_DIR` to isolate daemon/global state.
- Holds a per-repo lock before any update/index action.
- Writes `state.json` only after successful indexing.
- Records failures in `state.json` without pretending the index is ready.
- Exits nonzero on refresh failure so cron/systemd can surface the failure.
- Emits one lightweight failure record suitable for `dx-alerts`/operator
  inspection; do not require a long-running monitoring service.
- Stops the scoped daemon after each run; on timeout, kills only PIDs tied to
  that repo's `COCOINDEX_CODE_DIR`.

Minimum supported `ccc` version: `0.2.31` until the implementation proves a
newer version. The wrapper must treat unknown `state.json.schema_version` values
as `stale`, not crash or assume compatibility.

## Architecture

```text
~/.cache/agent-semantic-indexes/
  agent-skills/
    repo/                  # non-canonical clone/surface
    coco-global/           # COCOINDEX_CODE_DIR
    state.json             # readiness metadata
    refresh.log
    refresh.lock
  prime-radiant-ai/
    repo/
    coco-global/
    state.json
```

`state.json` should include at minimum:

```json
{
  "schema_version": 1,
  "repo_name": "agent-skills",
  "source_remote": "git@github.com:stars-end/agent-skills.git",
  "source_branch": "master",
  "index_surface": "/home/fengning/.cache/agent-semantic-indexes/agent-skills/repo",
  "indexed_head": "40-char-sha",
  "started_at": "2026-05-03T00:00:00Z",
  "finished_at": "2026-05-03T00:06:47Z",
  "status": "success",
  "exit_code": 0,
  "matched_files": 832,
  "chunks": 8340,
  "db_bytes": 34603008,
  "ccc_version": "0.2.31",
  "embedding_provider": "sentence-transformers",
  "embedding_model": "Snowflake/snowflake-arctic-embed-xs"
}
```

External data surface ownership:

- `~/.cache/agent-semantic-indexes/` is operational cache state, not repository
  source of truth.
- Implementation must update `docs/architecture/DATA_AND_STORAGE.md` and any
  relevant brownfield map stale-if entries so this cache surface has explicit
  ownership and rollback guidance.

Configuration lives under a component directory:

```text
configs/semantic-index/repositories.json
```

Do not add a flat root-level `configs/semantic-index-repos.json`.

Resolver policy:

- Use `configs/semantic-index/repositories.json` as the single mapping from
  repo name to canonical path, remote, branch, and index root.
- For `/tmp/agents/<beads-id>/<repo-name>` paths, resolve by exact
  allowlisted `<repo-name>` basename.
- For canonical clone paths, resolve by exact realpath match to configured
  canonical paths.
- For unknown repos or ambiguous paths, fail closed with `missing`.
- Do not use fuzzy matching.

## Beads Structure

| ID | Role | Gate |
|---|---|---|
| `bd-9n1t2.31` | Epic | All implementation, tests, review, and merge complete. |
| `bd-9n1t2.31.1` | Spec | This spec committed and reviewed by `dx-review`. |
| `bd-9n1t2.31.2` | Wrapper | `semantic-search` readiness/query contract implemented and tested. |
| `bd-9n1t2.31.3` | Cron/systemd | Scheduled refresh workflow implemented and tested. |
| `bd-9n1t2.31.4` | Integration | Worker PRs reviewed, fixed, validated, and merged. |

Blocking edges:

- `.31.1` blocks `.31.2`
- `.31.1` blocks `.31.3`
- `.31.2` and `.31.3` block `.31.4`

## Implementation Slices

### Slice A: Wrapper and Readiness

Owned paths:

- `scripts/semantic-search`
- `scripts/semantic_search.py`
- `tests/test_semantic_search.py`
- `tests/semantic_index_fixtures.py`
- `docs/semantic-search.md`
- `extended/llm-tldr/SKILL.md`
- `fragments/dx-global-constraints.md`
- generated `AGENTS.md` / `dist/*` after `make publish-baseline`

Required behavior:

- Metadata-based freshness; do not use `.git/index` mtime as truth.
- Configurable index root, defaulting to `~/.cache/agent-semantic-indexes`.
- Worktree resolver from `/tmp/agents/<beads-id>/<repo>` to `<repo-name>`.
- Routing docs remove `llm-tldr` semantic as the default first-hop and describe
  `semantic-search` as optional warmed hints only.
- Query and status paths assert no raw `ccc` invocation.
- Bounded direct query reads use the ccc Python environment and warmed SQLite
  DB without going through the ccc daemon request path.

### Slice B: Refresh Workflow and Cron

Owned paths:

- `configs/semantic-index/repositories.json`
- `scripts/semantic-index-refresh`
- `scripts/semantic_index_refresh.py`
- `scripts/semantic-index-cron.sh` or systemd-compatible wrapper
- `tests/test_semantic_index_refresh.py`
- `tests/semantic_index_fixtures.py` (reuse only; Worker A owns shared fixture)
- `docs/semantic-search.md`
- `docs/architecture/DATA_AND_STORAGE.md`
- relevant brownfield map stale-if docs if implementation changes covered paths

Required behavior:

- `--repo-name <name>` and `--all`.
- `--dry-run` prints intended operations and exits without clone/pull/index.
- Allowlist rejects unknown repos.
- Per-repo lock prevents concurrent refresh.
- Timeout knobs for init, doctor, index, status, and daemon stop.
- Writes `state.json` for success and failure.
- Reads/writes only schema version `1`; unknown schema versions are non-ready.
- Refresh failures exit nonzero and leave an inspectable failure state for
  cron/systemd and `dx-alerts` style checks.
- Cleans scoped daemon after timeout.
- Supports hourly cron/systemd invocation but does not install/enable timers
  without an explicit operator command.

Doc ownership rule:

- Worker A owns the query contract docs and routing text.
- Worker B owns refresh/cron docs.
- If both need `docs/semantic-search.md`, Worker B appends/edits only the
  refresh section and must preserve Worker A's query/status wording.

## Validation Gates

Workers must pass the relevant subset before PR handoff. Integration must pass
the full set before merge.

### Unit Tests

```bash
python3 -m pytest tests/test_semantic_search.py tests/test_semantic_index_refresh.py
```

Required test cases:

- `status=missing` with no metadata/DB.
- `status=indexing` when lock/state says refresh in progress.
- `status=stale` when indexed HEAD differs from canonical HEAD.
- `status=ready` with valid metadata and no raw `ccc status` call.
- `query` never invokes raw `ccc`.
- `query` falls back cleanly for missing/indexing/stale.
- `query` times out and falls back cleanly on slow direct query.
- refresh dry-run does not clone, pull, init, or index.
- refresh rejects non-allowlisted repo.
- refresh lock prevents concurrent run.
- refresh failure writes non-ready state.
- refresh success writes state with indexed HEAD, timestamps, DB bytes, and
  observed file/chunk counts when parsable.
- unknown `state.json.schema_version` returns non-ready.
- worktree resolver exact matches allowlisted repo names and fails closed on
  unknown paths.
- routing docs no longer instruct semantic discovery to call `llm-tldr` first.
- external cache surface is documented in architecture storage docs.

### Shell Smoke Tests

```bash
tmp=$(mktemp -d)
git clone --no-hardlinks /home/fengning/llm-common "$tmp/llm-common"
COCOINDEX_CODE_DIR="$tmp/coco-global" timeout 120 ccc init --force
COCOINDEX_CODE_DIR="$tmp/coco-global" timeout 180 ccc index
scripts/semantic-search status --repo "$tmp/llm-common"
scripts/semantic-search query --repo "$tmp/llm-common" "OpenRouter provider config" --limit 3
```

The exact smoke can use a stubbed direct query runner in CI; one real local
smoke should be recorded before merge on epyc12.

### Repo Hygiene

```bash
make publish-baseline
bash scripts/check-derived-freshness.sh
git diff --check
~/agent-skills/scripts/dx-verify-clean.sh
```

### Review Gates

```bash
dx-review doctor --worktree /tmp/agents/bd-9n1t2.31.1/agent-skills
dx-review run \
  --beads bd-9n1t2.31.1 \
  --worktree /tmp/agents/bd-9n1t2.31.1/agent-skills \
  --prompt-file docs/specs/2026-05-03-ccc-canonical-semantic-index-workflows.md \
  --template architecture-review \
  --wait \
  --timeout-sec 900
dx-review summarize --beads bd-9n1t2.31.1
```

Implementation PRs must receive code review after worker handoff. Findings must
be fixed or explicitly accepted before merge.

## Risks

| Risk | Mitigation |
|---|---|
| CPU contention on epyc12 | schedule off critical hours; one repo lock; configurable timeout/nice/ionice. |
| Daemon survives timeout | isolate `COCOINDEX_CODE_DIR`; stop daemon; kill only scoped PIDs. |
| Stale hints mislead agents | status returns `stale`; query refuses non-ready indexes. |
| Worktree mismatch | results must label indexed HEAD and index surface path. |
| CI cannot run real `ccc` | unit tests stub `ccc`; local epyc12 smoke records real `ccc` behavior. |

## Rollback

- Disable cron/systemd timer.
- Remove or rename `~/.cache/agent-semantic-indexes`.
- Leave `semantic-search` wrapper installed; it will return `missing`.
- Restore default agent guidance to `rg`/direct reads only.

## First Executable Task

Run `dx-review` architecture review on this spec. If review passes or returns
minor actionable findings, dispatch two workers:

- Worker A: `bd-9n1t2.31.2`, wrapper/readiness.
- Worker B: `bd-9n1t2.31.3`, refresh/cron.

Both workers must use separate worktrees and must not mutate canonical clones.
