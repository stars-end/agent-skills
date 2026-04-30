# CocoIndex V1 Framework Bakeoff

**Date:** 2026-04-30
**BEADS_EPIC:** bd-9n1t2.30
**BEADS_SUBTASK:** bd-9n1t2.30.3
**Feature-Key:** bd-9n1t2.30.3
**Agent:** epyc12-claude-code
**Mode:** qa_pass
**Candidate:** CocoIndex V1 framework only, `cocoindex>=1.0.0`

## Verdict

**defer CocoIndex V1 to P2+**

CocoIndex V1 is viable as an incremental local state engine, but not as a near-term replacement for `llm-tldr`, grepai, or targeted `rg`/direct reads in the agent critical path. The framework proves embedded LMDB state and per-file memoization, but we would still need to own a code-specific harness: file filtering, chunking, metadata schema, target storage, query API, semantic embeddings/vector target, readiness checks, error parsing, and Git/worktree cleanup rules.

That ownership cost is too high for P0/P1 while the default routing decision can be handled by `rg`, direct reads, and `serena`.

## Explicit Exclusion

This memo does not evaluate `cocoindex-code`, `ccc`, `ccc daemon`, or `cocoindex-code 0.2.31`.

PR #602 is the old superseded `ccc` lane and is not used as evidence here. `ccc` was checked only by `command -v ccc` to confirm absence; it was not run.

## Source Context

Coordinator synthesis PR read first:

- PR: https://github.com/stars-end/agent-skills/pull/603
- Head SHA: `260210c62f54a22fa8fedaccde60ac285f049d0e`
- File: `docs/architecture/2026-04-30-final-llm-tldr-replacement-bakeoff-synthesis.md`

The synthesis already decides `ALL_IN_NOW` for removing `llm-tldr semantic` from first-hop routing, while leaving CocoIndex V1 as this focused framework-only rerun.

Official V1 docs used for harness shape:

- https://cocoindex.io/docs/getting_started/quickstart/
- https://cocoindex.io/blogs/cocoindex-v1/

The V1 quickstart shows `COCOINDEX_DB=./cocoindex.db`, `@coco.fn(memo=True)`, `localfs.walk_dir`, `coco.mount_each`, and `localfs.declare_file`. The V1 launch post states that V1 uses embedded LMDB for internal state rather than requiring Postgres.

## Infra Preflight

Commands:

```bash
timeout 60 uvx --from 'cocoindex>=1.0.0' cocoindex --version
command -v ccc >/dev/null 2>&1; rc=$?; if [ "$rc" -eq 0 ]; then echo 'ccc_present'; else echo 'ccc_absent'; fi
```

Results:

```text
cocoindex version 1.0.2
ccc_absent
```

No blocker. Expected V1 framework path is available.

## Harness Shape

Disposable path:

```text
/tmp/cocoindex-v1-framework-bench
```

Input setup:

```bash
cp -a /tmp/agents/bd-9n1t2.30.3/agent-skills/. /tmp/cocoindex-v1-framework-bench/agent-skills-src/
cp -a /home/fengning/affordabot/. /tmp/cocoindex-v1-framework-bench/affordabot-src/
rm -rf /tmp/cocoindex-v1-framework-bench/agent-skills-src/.git \
  /tmp/cocoindex-v1-framework-bench/affordabot-src/.git \
  /tmp/cocoindex-v1-framework-bench/agent-skills-src/node_modules \
  /tmp/cocoindex-v1-framework-bench/affordabot-src/node_modules \
  /tmp/cocoindex-v1-framework-bench/agent-skills-src/.venv \
  /tmp/cocoindex-v1-framework-bench/affordabot-src/.venv
```

`rsync` was not installed on this host, so plain copy was used. That is not a CocoIndex product failure.

Minimal V1 app shape:

```python
import hashlib
import json
import pathlib

import cocoindex as coco
from cocoindex.connectors import localfs
from cocoindex.resources.file import PatternFilePathMatcher

INCLUDED_PATTERNS = ["**/*.py", "**/*.md", "**/*.ts", "**/*.tsx", "**/*.js",
                     "**/*.jsx", "**/*.json", "**/*.toml", "**/*.yaml",
                     "**/*.yml", "**/*.sh"]

@coco.fn(memo=True)
def process_file(file: localfs.File, outdir: pathlib.Path) -> None:
    path = file.file_path.path
    text = file.file_path.resolve().read_text(encoding="utf-8", errors="ignore")
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    record = {
        "path": str(path),
        "suffix": path.suffix,
        "sha256": digest,
        "bytes": len(text.encode("utf-8")),
        "lines": text.count("\n") + (1 if text else 0),
        "preview": text[:800],
    }
    localfs.declare_file(
        outdir / f"{digest[:16]}.json",
        json.dumps(record, sort_keys=True) + "\n",
        create_parent_dirs=True,
    )

@coco.fn
async def app_main(sourcedir: pathlib.Path, outdir: pathlib.Path) -> None:
    files = localfs.walk_dir(
        sourcedir,
        recursive=True,
        path_matcher=PatternFilePathMatcher(included_patterns=INCLUDED_PATTERNS),
    )
    await coco.mount_each(process_file, files.items(), outdir)

app = coco.App(
    "CodeMetadataIndex",
    app_main,
    sourcedir=pathlib.Path("./input"),
    outdir=pathlib.Path("./out"),
)
```

The first implementation attempt incorrectly used `file.content`; CocoIndex reported `AttributeError: 'File' object has no attribute 'content'` for every mounted file but still exited 0. The correct V1 pattern is `file.file_path.resolve().read_text(...)`.

## Timings

All update commands used:

```bash
env COCOINDEX_DB=./cocoindex.db timeout 300 uvx --from 'cocoindex>=1.0.0' cocoindex update main.py --force
```

### agent-skills

Input symlink:

```bash
ln -s agent-skills-src input
```

Initial update:

```text
rc=0
shell elapsed: 31.418s
CocoIndex elapsed: 28.1s
process_file: 861 total | 861 added
```

State/output:

```text
find out -type f | wc -l => 801
du -sh cocoindex.db out => 824K cocoindex.db, 3.2M out
```

The output count is lower than mounted-file count because the harness names output files by content hash; duplicate files collapse to the same JSON target name. A production harness would need a stable path-based ID or multi-record target.

Second update with no changes:

```text
rc=0
shell elapsed: 17.906s
CocoIndex elapsed: 15.1s
process_file: 861 total | 861 unchanged
```

Incremental update after appending one line to `agent-skills-src/docs/architecture/README.md`:

```text
rc=0
shell elapsed: 17.206s
CocoIndex elapsed: 13.4s
process_file: 861 total | 1 reprocessed, 860 unchanged
```

### affordabot

Input symlink:

```bash
ln -s affordabot-src input
```

Initial update:

```text
rc=0
shell elapsed: 49.404s
CocoIndex elapsed: 45.4s
process_file: 1686 total | 1686 added
```

State/output:

```text
find out -type f | wc -l => 917
du -sh cocoindex.db out => 1.8M cocoindex.db, 3.7M out
```

Second update with no changes:

```text
rc=0
shell elapsed: 27.374s
CocoIndex elapsed: 23.4s
process_file: 1686 total | 1686 unchanged
```

Incremental update after appending one line to `affordabot-src/README.md`:

```text
rc=0
shell elapsed: 23.574s
CocoIndex elapsed: 21.3s
process_file: 1686 total | 1 reprocessed, 1685 unchanged
```

## State, Cache, and Git Behavior

`COCOINDEX_DB=./cocoindex.db` creates a local LMDB state file at the chosen path. The target data in this harness is a local `out/` directory. Neither should be committed.

Recommended worktree `.gitignore` additions if we build on this:

```gitignore
cocoindex.db
cocoindex.db-*
.cocoindex/
cocoindex-out/
```

The framework state is cleanly local and does not require a daemon or Postgres for bookkeeping. That is a strong positive compared with hidden long-lived index state.

## Query/Search Evidence

CocoIndex V1 did not provide a ready code-search query surface in this framework test. The harness exported one JSON file per processed content hash, then used `rg` over those JSON targets.

Command:

```bash
rg -n --ignore-case 'scrape|listing|vehicle' out > query-affordabot.log
```

Result:

```text
rc=0
elapsed=0.016s
142 lines
```

Baseline direct `rg` over `agent-skills` docs/core/extended:

```bash
rg -n --ignore-case 'agent cognitive load|cognitive' docs core extended
```

Result:

```text
rc=0
elapsed=0.223s
64 lines
```

This is not semantic retrieval. A true semantic query harness would require adding chunking plus embeddings plus a target such as LanceDB, sqlite-vec, pgvector, or another local vector store, and then a query API/wrapper for agents. That harness complexity is the finding.

## Timeout and Failure Behavior

Bounded timeout command:

```bash
timeout 1 env COCOINDEX_DB=./cocoindex.db uvx --from 'cocoindex>=1.0.0' cocoindex update main.py --force
```

Result:

```text
rc=124
elapsed=1.122s
```

Bad harness behavior:

```text
AttributeError: 'File' object has no attribute 'content'
process_file: 861 total | 861 errors
process exited with code 0
```

Implication: a production wrapper must parse the update output for error counters or inspect a structured status surface if one exists. Exit code alone is not enough.

## Comparison

| Candidate | Critical-path fit | Evidence |
|---|---|---|
| `rg` / direct reads | best now | No setup, no hidden state, subsecond targeted lookup in this run. |
| grepai local | P2+ async/on-demand | Simpler query product shape than V1, but needs managed Ollama/model/index readiness from the other worker lane. |
| CocoIndex V1 | P2+ substrate | Good local LMDB/memoization engine, but no owned code-search product without harness work. |

## Code We Would Need To Own

Minimum useful owned layer:

- repo scanner and include/exclude policy
- chunker for code, Markdown, and config files
- stable path-based IDs instead of content-hash-only output names
- target choice and schema
- embedding provider abstraction if semantic search is required
- local vector target setup and cleanup
- query CLI with JSON output and nonzero failures on invalid state
- readiness checks for `COCOINDEX_DB`, state corruption, missing target, and schema drift
- output parser that treats component errors as failures even when process exit is 0
- `.gitignore` and worktree cleanup rules
- benchmark fixtures and regression tests across representative repos

This is enough owned surface that CocoIndex V1 should not become a default agent route during the current `llm-tldr` removal.

## Agent Cognitive-Load Assessment

V1 lowers one burden: agents do not have to manage a daemon or Postgres for framework bookkeeping.

It adds several burdens before it can help agents:

- know which harness app to run
- know which local state path is authoritative
- know whether update errors are hidden behind exit code 0
- understand that “unchanged” still costs a full source walk
- know that query quality depends on our target/query layer, not CocoIndex alone

Current net: higher cognitive load than `rg`/direct reads.

## Founder HITL-Load Assessment

Adopting V1 now would create founder review surfaces around architecture, owned harness behavior, vector target choice, embedding privacy, rollout, and support. That is not justified for P0/P1 because the immediate founder pain is repeated failed `llm-tldr` routing, and that pain can be removed without adding a new framework.

P2+ is reasonable if the product goal becomes a first-party local semantic index with explicit ownership.

## Final Recommendation

Use CocoIndex V1 as a future substrate candidate only.

Do not build on CocoIndex V1 now for default agent discovery. Remove `llm-tldr semantic` from first-hop routing and use `rg`/direct reads plus `serena` for known-symbol edits. Revisit CocoIndex V1 at P2+ only with an explicit implementation plan for the owned code-index/search harness.
