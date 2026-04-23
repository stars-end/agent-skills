# 2026-04-08 Analysis Challenger Benchmark Contract

## Objective
Run one final, narrow benchmark wave on analysis-layer challengers before any strategic replacement decision.

This contract exists because prior memo waves mixed analysis with editing and overclaimed replacement parity from semantic search alone.

## In Scope
Analysis / retrieval / discovery only.

Primary candidates under direct challenge:
- `llm-tldr`
- `grepai`
- `ck`
- `cocoindex-code`

Secondary controls / context only:
- Sourcegraph / Cody
- Zoekt
- Continue custom RAG
- one relevant DIY vector stack if needed to explain design boundaries

## Out of Scope
- editing tool selection
- memory tooling
- implementation or migration work
- hosted-only architecture decisions

## Decision Standard
A challenger does **not** count as a replacement for `llm-tldr` unless it demonstrates parity or a compelling tradeoff on:
1. semantic discovery
2. exact structural tracing
3. call graph / callers / imports / reverse-impact style analysis
4. architecture understanding across files
5. acceptable operational burden in worktrees

Strong semantic retrieval **alone** is not enough.

## Required Benchmark Tasks
Each delegate must use the same task categories.

### Category A: Semantic Discovery
Questions like:
- where does feature X live?
- what code relates to concept Y?
- which files are involved in workflow Z?

### Category B: Exact Structural Tracing
Questions like:
- what calls this function?
- what does this entrypoint depend on?
- trace from API handler to downstream service/helper

### Category C: Reverse Impact
Questions like:
- if file/function X changes, what else is likely affected?
- what tests/components are downstream of this symbol/path?

### Category D: Architecture Understanding
Questions like:
- what are the major layers/modules involved in subsystem X?
- how is responsibility split across files/components?

## Required Evaluation Criteria
For each candidate, score:
- semantic discovery: `full` / `partial` / `none`
- exact structural tracing: `full` / `partial` / `none`
- call graph / impact: `full` / `partial` / `none`
- architecture understanding: `full` / `partial` / `none`
- local/worktree safety: `full` / `partial` / `none`
- determinism/scriptability for agents: `full` / `partial` / `none`
- runtime burden: `low` / `medium` / `high`
- wrapper-tax risk: `low` / `medium` / `high`

## Candidate-Specific Questions
### `llm-tldr`
- Is current MCP/runtime pain a tooling-surface issue rather than an analysis-capability issue?
- Which analysis surfaces actually remain unmatched by challengers?

### `grepai`
- Are its trace/call-graph surfaces materially close to `llm-tldr`?
- Does watcher/daemon burden materially reduce its operational fit?

### `ck`
- Is it best understood as semantic/hybrid retrieval only?
- Does it have any real structural/impact capability beyond search + regex hybridization?

### `cocoindex-code`
- Does AST-based chunking materially improve structural understanding, or is it still primarily semantic retrieval?
- What daemon/runtime burden exists in actual use?

## Required Evidence Shape
Each delegate must produce:
1. one benchmark memo
2. one comparison table using the same labels above
3. explicit notes on what the tool cannot do
4. a clear verdict among:
- `keep llm-tldr`
- `narrow llm-tldr and benchmark challengers`
- `replace llm-tldr with <candidate>`
- `split analysis layer`

## Synthesis Rule
If neither challenger pair demonstrates structural + impact parity, the orchestrator should keep `llm-tldr` and treat challengers as niche semantic-discovery tools or future pilots.
