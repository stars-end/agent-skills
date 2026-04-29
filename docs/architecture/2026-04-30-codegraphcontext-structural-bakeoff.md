# CodeGraphContext Structural Bakeoff

**Date:** 2026-04-30  
**BEADS_EPIC:** bd-9n1t2.30  
**BEADS_SUBTASK:** bd-9n1t2.30.2  
**FEATURE_KEY:** bd-9n1t2.30.2  
**Mode:** qa_pass  
**Candidate:** CodeGraphContext 0.4.2  
**Verdict:** complement llm-tldr structural

## Decision

CodeGraphContext should not replace `llm-tldr calls/imports/impact/context` for critical-path structural work yet.

It is good enough to complement or demote some narrow `llm-tldr` structural tasks:

- Use CodeGraphContext for deterministic caller/callee lookup, broad content search, complexity sweeps, dead-code sweeps, and quick class-hierarchy checks after a repo has been indexed.
- Keep `llm-tldr context` for compact call-neighborhood extraction.
- Keep `llm-tldr imports` for file-level import extraction.
- Do not route critical agent paths through CodeGraphContext when JSON output is required.

The decisive blockers for replacement are missing JSON output, weaker import/dependency behavior on the target file, global default state outside the worktree unless configured, and no `llm-tldr context` equivalent that returns a compact token-budgeted neighborhood.

## Sources Read

- Beads task: `bdx show bd-9n1t2.30.2 --json`
- Prior PR refs:
  - `git fetch origin pull/593/head:pr-593 pull/594/head:pr-594 --prune`
  - `git show pr-593:docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md`
  - `git show pr-593:docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md`
  - `git show pr-594:docs/investigations/TECHLEAD-REVIEW-llm-tldr-competitor-bakeoff.md`
- Official source/docs:
  - `https://github.com/CodeGraphContext/CodeGraphContext`
  - README states CodeGraphContext is an MCP server and CLI that indexes local code into a graph database, supports relationship analysis including callers/callees/class hierarchies/call chains, and supports embedded FalkorDB Lite or KuzuDB plus Neo4j.
- Installed CLI:
  - `cgc help`
  - `cgc find --help`
  - `cgc analyze --help`
  - `cgc doctor`

## Setup Commands

```bash
dx-worktree create bd-9n1t2.30.2 agent-skills
dx-worktree create bd-9n1t2.30.2 affordabot
cd /tmp/agents/bd-9n1t2.30.2/agent-skills

BEADS_DIR=$HOME/.beads-runtime/.beads bdx show bd-9n1t2.30.2 --json
git fetch origin pull/593/head:pr-593 pull/594/head:pr-594 --prune

timeout 300 python -m venv /tmp/agents/bd-9n1t2.30.2/cgc-venv
timeout 300 /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/pip install -q codegraphcontext

timeout 120 /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc help
timeout 120 /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc find --help
timeout 120 /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc analyze --help
timeout 120 /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc doctor
```

Important setup note: default `cgc doctor` used `/home/fengning/.codegraphcontext`. To make state explicit and avoid polluting canonical clones, benchmark commands set `HOME=/tmp/agents/bd-9n1t2.30.2/cgc-home...`.

## Timing Table

| Step | Command | Result | Wall time |
|---|---|---:|---:|
| Create venv | `timeout 300 python -m venv /tmp/agents/bd-9n1t2.30.2/cgc-venv` | pass | 2.227s |
| Install CGC | `timeout 300 .../pip install -q codegraphcontext` | pass, warning: `typer 0.25.0 does not provide the extra 'all'` | 18.493s |
| Version | `cgc version` | `CodeGraphContext 0.4.2` | <1s |
| Doctor | `cgc doctor` | pass | about 5s |
| Index agent-skills | `timeout 120 env HOME=.../cgc-home cgc index /tmp/agents/.../agent-skills` | pass, 127 files, 1350 functions, 166 classes, 162 modules | 27.388s wall, CLI reported 25.76s |
| Index affordabot | `timeout 120 env HOME=.../cgc-home-affordabot cgc index /tmp/agents/.../affordabot` | pass, 539 files, 3115 functions, 368 classes, 527 modules | 1:54.12 wall, CLI reported 111.52s |
| Find symbol | `cgc find name apply_containment_patches` | 2 matches | 2.031s |
| Callees | `cgc analyze calls apply_containment_patches --file scripts/tldr_contained_runtime.py` | 5 callees | 1.774s first, 2.204s repeat |
| Callers | `cgc analyze callers apply_containment_patches --file scripts/tldr_contained_runtime.py` | 4 callers | 1.958s |
| Deps/imports | `cgc analyze deps tldr_contained_runtime` | no dependency information found | 1.369s |
| Complexity | `cgc analyze complexity --threshold 10` | 20 functions | 2.110s |
| Dead code | `cgc analyze dead-code` | 50 functions, warning about entrypoints/callbacks | 1.806s |
| Class tree | `cgc analyze tree Config` | no parent/child classes | 1.068s |
| Content search | `cgc find content semantic_index_missing` | 5 matches | 1.799s |
| Missing symbol | `cgc analyze calls definitely_not_a_symbol` | "No function calls found" with exit 0 | 2.397s |
| JSON attempt | `cgc --json analyze calls ...` | exit 2, no such option | about 1s |
| JSON attempt | `cgc analyze calls ... --json` | exit 2, no such option | about 1s |

## Structural Capability Table

| Capability | CodeGraphContext result | Replacement quality |
|---|---|---|
| Caller lookup | Good. `apply_containment_patches` returned `main`, `run_cli`, `run_mcp`, `run_daemon`; Affordabot `process_raw_scrape` returned 20 callers. | Can replace `llm-tldr impact` for simple caller lookup when human-readable output is acceptable. |
| Callee lookup | Good. `apply_containment_patches` returned the five patch helpers. Affordabot `process_raw_scrape` returned 20 callees, but with repeated entries for repeated calls. | Can complement/replace `llm-tldr calls` for narrow symbol checks. |
| Imports/module relationships | Weak on target. `cgc analyze deps tldr_contained_runtime` returned no dependency information. | Cannot replace `llm-tldr imports`. |
| Class hierarchy | Supported by `cgc analyze tree`; target `Config` had no parents/children. | Useful when a known class is involved. |
| Dead-code detection | Supported; returned 50 possible unused functions with explicit caveat. | Useful as advisory sweep, not authoritative gate. |
| Complexity analysis | Supported; returned ranked functions and complexity scores. | Strong complement; `llm-tldr context` also includes complexity locally. |
| Content search | Supported; found source/docstring matches and returned code elements. | Useful, but exact text search remains faster with `rg`. |
| JSON output | Not supported by CLI flags tested. | Blocking for critical-path agent automation. |
| Repeated query latency | About 1-2.4s including CLI startup/FalkorDB Lite init. | Operationally acceptable after indexing. |
| Failure legibility | CLI errors are clear for invalid flags. Missing symbol returns exit 0 with "No function calls found". | Better than silent daemon failures, but exit 0 on absent symbol is not machine-safe. |
| No-LLM/no-embedding path | Yes. Indexing and queries used tree-sitter plus local graph DB; no API keys, LLM calls, or embedding model downloads observed. | Strong. |

## Representative Targets

### agent-skills

`scripts/tldr_contained_runtime.py`

```bash
timeout 120 env HOME=/tmp/agents/bd-9n1t2.30.2/cgc-home \
  /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc find name apply_containment_patches

timeout 120 env HOME=/tmp/agents/bd-9n1t2.30.2/cgc-home \
  /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc analyze calls apply_containment_patches \
  --file scripts/tldr_contained_runtime.py

timeout 120 env HOME=/tmp/agents/bd-9n1t2.30.2/cgc-home \
  /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc analyze callers apply_containment_patches \
  --file scripts/tldr_contained_runtime.py
```

Find result: located `apply_containment_patches` at `scripts/tldr_contained_runtime.py:512`.

Callee result: `_patch_daemon_response_serialization`, `_patch_mcp_daemon_startup`, `_patch_path_join`, `_patch_semantic_autobootstrap`, `_patch_semantic_markers`.

Caller result: `main`, `run_cli`, `run_mcp`, `run_daemon`.

`extended/llm-tldr/SKILL.md`

CGC does not analyze Markdown skill bodies as code symbols. Content search can find text, but it does not replace semantic/context tooling for skill prose.

### affordabot

Representative module discovered by source/test scan:

`backend/services/ingestion_service.py`

```bash
timeout 120 env HOME=/tmp/agents/bd-9n1t2.30.2/cgc-home-affordabot \
  /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc find name IngestionService

timeout 120 env HOME=/tmp/agents/bd-9n1t2.30.2/cgc-home-affordabot \
  /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc analyze calls process_raw_scrape \
  --file backend/services/ingestion_service.py

timeout 120 env HOME=/tmp/agents/bd-9n1t2.30.2/cgc-home-affordabot \
  /tmp/agents/bd-9n1t2.30.2/cgc-venv/bin/cgc analyze callers process_raw_scrape \
  --file backend/services/ingestion_service.py
```

Find result: located `IngestionService` at `backend/services/ingestion_service.py:23`.

Caller result: 20 callers, including cron, verification, service, and tests. This is useful cross-codebase structural evidence.

Callee result: 20 callees, but repeated entries such as `_persist_ingestion_truth` show that results are raw call sites rather than deduplicated callee summaries.

## Comparison To llm-tldr Structural Tools

```bash
timeout 60 /home/fengning/agent-skills/scripts/tldr-daemon-fallback.sh imports \
  --file /tmp/agents/bd-9n1t2.30.2/agent-skills/scripts/tldr_contained_runtime.py
```

Result: pass in 2.006s, JSON output with import records and `status: ok`.

```bash
timeout 60 /home/fengning/agent-skills/scripts/tldr-daemon-fallback.sh impact \
  --repo /tmp/agents/bd-9n1t2.30.2/agent-skills \
  --function apply_containment_patches
```

Result: pass in 2.005s, JSON output, but returned `"callers": []` for a symbol where CGC found four callers.

```bash
timeout 60 /home/fengning/agent-skills/scripts/tldr-daemon-fallback.sh calls \
  --repo /tmp/agents/bd-9n1t2.30.2/agent-skills
```

Result: pass in 12.266s, JSON output with 1310 graph edges. Good for machine processing, noisy for human first-hop use.

```bash
timeout 60 /home/fengning/agent-skills/scripts/tldr-contained.sh context \
  apply_containment_patches \
  --project /tmp/agents/bd-9n1t2.30.2/agent-skills \
  --depth 2
```

Result: pass in 11.160s, returned a compact 19-function, approximately 1275-token call neighborhood with complexity and nested callees.

```bash
timeout 60 rg -n "def apply_containment_patches|apply_containment_patches\(" \
  scripts/tldr_contained_runtime.py
```

Result: pass in 0.005s, found the definition and three same-file calls.

Comparison:

- CGC beat `llm-tldr impact` on the caller lookup target.
- `llm-tldr imports` beat CGC on file-level import extraction.
- `llm-tldr calls` has better JSON/machine-readability, but output is broad and large.
- `llm-tldr context` still has no CGC equivalent because CGC reports relationships, not compact extracted context.
- `rg` remains the fastest exact text fallback and is enough for many same-file questions.

## No-LLM Critical-Path Assessment

CodeGraphContext passes the local/no-LLM/no-embedding requirement for structural work. The install pulled parser/database dependencies, but runtime indexing and querying did not require API keys, LLM calls, embedding calls, or model downloads. It is a deterministic static graph path.

However, critical-path replacement also needs machine-readable output and predictable state. CGC fails that bar today because the CLI does not expose JSON for the tested commands, missing-symbol lookup exits successfully, and default state is global under `$HOME/.codegraphcontext` unless agents remember to configure `HOME`, context mode, or a named/per-repo context.

## State And Worktree Behavior

Observed isolated state with `HOME=/tmp/agents/bd-9n1t2.30.2/cgc-home`:

```text
/tmp/agents/bd-9n1t2.30.2/cgc-home/.codegraphcontext/global/db/falkordb
/tmp/agents/bd-9n1t2.30.2/cgc-home/.codegraphcontext/global/db/falkordb.settings
/tmp/agents/bd-9n1t2.30.2/cgc-home/.codegraphcontext/global/.cgcignore
/tmp/agents/bd-9n1t2.30.2/cgc-home/.codegraphcontext/logs
/tmp/agents/bd-9n1t2.30.2/cgc-home/.codegraphcontext/config.yaml
/tmp/agents/bd-9n1t2.30.2/cgc-home/.cache/tree-sitter-language-pack/v1.6.2
```

No `.codegraphcontext` directory was created in the `agent-skills` worktree during this benchmark because the default mode was global and `HOME` was redirected.

The default user experience is not worktree-first. First run says:

```text
global    - One shared graph for all projects (default)
per-repo  - Each repo gets its own .codegraphcontext/ folder
named     - Create named workspaces
```

For multi-agent work, CGC must be wrapped to use either a per-task `HOME` or a per-repo/named context. Otherwise unrelated workers can share global graph state and make results harder to trust.

## Failure Modes

- Invalid JSON flag is legible: `No such option: --json`, exit 2.
- Missing symbol is human-legible but machine-ambiguous: `No function calls found for 'definitely_not_a_symbol'`, exit 0.
- Dependency query on `tldr_contained_runtime` returned `No dependency information found`, exit 0, despite the file having many imports.
- Output uses Rich tables with wrapped paths, which is readable for humans but awkward for automated parsers.
- Affordabot index finished close to the timeout: 114.12s wall under a 120s bound. That is acceptable but not boring.
- Default config/state is global under `$HOME`, so ambient state can leak across worktrees if not explicitly isolated.

## Agent Cognitive Load

CGC is easier than `llm-tldr` in one narrow way: the CLI surface is discoverable, and the structural commands map directly to tasks:

- `cgc analyze calls`
- `cgc analyze callers`
- `cgc analyze deps`
- `cgc analyze tree`
- `cgc analyze complexity`
- `cgc analyze dead-code`
- `cgc find content`

But it adds new cognitive load around state mode, database backend, context selection, and non-JSON output. Agents would need a wrapper contract like:

```bash
HOME=/tmp/agents/<beads-id>/cgc-home cgc index <worktree>
HOME=/tmp/agents/<beads-id>/cgc-home cgc analyze callers <symbol> --file <file>
```

Without that wrapper, agents will use ambient `$HOME/.codegraphcontext` state and may not know whether the graph corresponds to the current worktree.

## Founder HITL Load

Founder HITL load is lower than llm-tldr daemon/MCP hydration work if CGC is used manually for a spike. It is not lower enough for P0/P1 replacement:

- A wrapper or routing contract change is required.
- Agents must be taught the state isolation rule.
- JSON absence means any automation needs brittle table parsing or custom integration against CGC internals.
- Large repos may take close to the 120s bound to index.

This is a `DEFER_TO_P2_PLUS` operational profile for replacement, but acceptable as a complementary manual/agent-advisory tool.

## Final Verdict

**Verdict:** complement llm-tldr structural

Reason:

- Replace for simple human-readable caller/callee checks after indexing: yes.
- Replace `llm-tldr imports`: no.
- Replace `llm-tldr context`: no.
- Replace JSON/machine-readable critical-path structural automation: no.
- Replace semantic discovery: out of scope; CGC is structural, not embedding/semantic search.

Recommended routing:

```text
caller/callee quick check -> CodeGraphContext if indexed, otherwise rg/direct read
imports -> llm-tldr imports or direct parser/read
compact call neighborhood/context -> llm-tldr context
automation requiring JSON -> llm-tldr JSON tools or direct scripts, not CGC CLI
dead-code/complexity sweeps -> CodeGraphContext advisory only
```

## PR Artifacts

PR_URL: https://github.com/stars-end/agent-skills/pull/601  
PR_HEAD_SHA: 2e63df032fff72412887b134ec9a6c91e23a1d1d  
BEADS_SUBTASK: bd-9n1t2.30.2
