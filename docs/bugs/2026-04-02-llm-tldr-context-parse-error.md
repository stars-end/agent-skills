# llm-tldr `context` Parse Error in MCP Runtime

- CLASS: `dx_loop_control_plane`
- NOT_A_PRODUCT_BUG: `true`
- Beads: `bd-58xq`
- Manifestation context: `bd-htga` work during `agent-skills` `dx-loop` control-plane investigation
- Related PR under investigation context: `agent-skills` PR #455 (`c47f2b6d115bb2debbcb1abaa606e0d5c016c34a`)

## Symptom

`llm-tldr context` failed in the MCP runtime with a JSON parse error on valid entrypoint requests:

- `Error executing tool context: Expecting value: line 1 column 1 (char 0)`

This forced fallback to direct file inspection during control-plane QA work.

## Environment / Triggering Context

- Host: local macOS canonical host
- Assistant runtime: Codex desktop runtime with MCP tools
- Repo under test: `/tmp/agents/bd-58xq/agent-skills`
- llm-tldr binary version: `tldr 1.5.2`
- Control-plane surface under investigation: `dx-loop`
- Source files first read from fetched PR state:
  - `docs/bugs/2026-04-02-dx-loop-empty-graph-false-complete.md`
  - `scripts/dx_loop.py`
  - `tests/dx_loop/test_v1_1_fixes.py`

## Expected Behavior

For valid entrypoint requests in the active worktree, `llm-tldr context` should return token-efficient structural context similar to the contained CLI output, without requiring fallback to direct repo reads.

## Exact Observed Behavior

In the MCP tool path, all attempted `context` requests failed with the same parse error:

1. `mcp__llm_tldr__context(project="/tmp/agents/bd-58xq/agent-skills", entry="cmd_status", depth=2, language="python")`
   - result: `Error executing tool context: Expecting value: line 1 column 1 (char 0)`
2. `mcp__llm_tldr__context(project="/tmp/agents/bd-58xq/agent-skills", entry="_reconcile_wave_state_for_surfaces", depth=2, language="python")`
   - result: `Error executing tool context: Expecting value: line 1 column 1 (char 0)`
3. `mcp__llm_tldr__context(project="/tmp/agents/bd-58xq/agent-skills", entry="load_config_file", depth=1, language="python")`
   - result: `Error executing tool context: Expecting value: line 1 column 1 (char 0)`

At the same time, nearby non-`context` MCP surfaces still worked:

1. `mcp__llm_tldr__search(project="/tmp/agents/bd-58xq/agent-skills", pattern="_reconcile_wave_state_for_surfaces|cmd_status", max_results=10)`
   - status: `ok`
2. `mcp__llm_tldr__extract(file="/tmp/agents/bd-58xq/agent-skills/scripts/dx_loop.py")`
   - status: `ok`
3. `mcp__llm_tldr__structure(project="/tmp/agents/bd-58xq/agent-skills", language="python", max_results=5)`
   - status: `ok`

## Reproduction Attempts

### Attempt A: MCP `context` against same-shape `dx_loop` entrypoints

Commands/tool invocations attempted:

- `mcp__llm_tldr__context(... entry="cmd_status" ...)`
- `mcp__llm_tldr__context(... entry="_reconcile_wave_state_for_surfaces" ...)`
- `mcp__llm_tldr__context(... entry="load_config_file" ...)`

Outcome:

- reproduced
- all three returned the same parse error

### Attempt B: MCP non-`context` surfaces in the same runtime

Commands/tool invocations attempted:

- `mcp__llm_tldr__search(...)`
- `mcp__llm_tldr__extract(...)`
- `mcp__llm_tldr__structure(...)`

Outcome:

- all succeeded
- failure does not look like a full `llm-tldr` outage

### Attempt C: Direct contained CLI `context` in the same worktree

Commands attempted:

```bash
./scripts/tldr-contained.sh context cmd_status --project /tmp/agents/bd-58xq/agent-skills --depth 2
./scripts/tldr-contained.sh context cmd_status --project .
```

Outcome:

- both succeeded and returned real context for `cmd_status`
- this materially weakens the hypothesis that the repo itself, the symbol, or base indexing state is invalid

### Attempt D: Warm path

Command attempted:

```bash
./scripts/tldr-contained.sh warm .
```

Outcome:

- not required to explain the MCP failure boundary
- no evidence from this pass that lack of warm/indexing is the primary cause of the observed MCP `context` parse error

## Fault Boundary Assessment

Current evidence points away from product code and away from a generic `llm-tldr` availability failure.

Most likely boundary is one of:

1. MCP/daemon `context` response path is returning empty or invalid JSON for `cmd=context`
2. MCP wrapper is receiving non-JSON output on the `context` socket path and surfacing the upstream `json.loads(...)` failure
3. daemon/runtime state is corrupt only for the `context` command family while leaving `search`/`extract`/`structure` healthy

Less likely based on this pass:

1. project-specific symbol issue
2. repo indexing issue
3. full MCP startup failure
4. full `llm-tldr` outage

## Code-Level Hypotheses

Observed code paths suggest a plausible empty-response boundary:

- upstream `tldr.mcp_server.context()` calls `_send_command(project, {"cmd": "context", ...})`
- upstream `_send_raw()` keeps reading socket chunks and finally calls `json.loads(b"".join(chunks))`
- if the daemon returns EOF with no bytes, that exact call would produce:
  - `Expecting value: line 1 column 1 (char 0)`

Relevant local files inspected during this QA pass:

- `scripts/tldr_contained_runtime.py`
- `scripts/tldr-mcp-contained.py`
- `scripts/tldr-mcp-contained-launch.py`

Important nuance:

- direct contained CLI `context` works
- MCP `context` fails
- therefore the likely fault boundary is not the underlying code-context engine alone; it is more likely in the daemon/MCP socket path or in how `context` is surfaced through MCP

## Affected Workflows

Affected:

- exact structural tracing during control-plane reviews
- low-token dependency/context gathering for `dx-loop` investigations
- any Codex MCP workflow that expects `llm-tldr context` to be the first precise static-analysis step

Not affected in this pass:

- product runtime behavior
- `dx-loop` product manifestation itself
- other tested MCP surfaces: `search`, `extract`, `structure`
- direct contained CLI `context`

## Workaround Currently Used

When `llm-tldr context` fails in MCP runtime:

1. continue with `llm-tldr` surfaces that still work (`search`, `extract`, `structure`) when useful
2. fall back to direct repo reads / targeted `rg`
3. keep the final handoff explicit that this was a tooling/control-plane routing exception, not a product defect

## Recommended Diagnostics / Next Debugging Steps

1. Capture the raw daemon response for `cmd=context` in the failing MCP runtime
   - confirm whether bytes received are zero, truncated, or non-JSON
2. Verify whether the contained runtime diagnostic wrapper in `scripts/tldr_contained_runtime.py` is actually intercepting this failure path for non-semantic commands
3. Run a manual JSONL probe against `scripts/tldr-mcp-contained.py` for a `context` tool call
   - compare with a direct CLI `context` run in the same worktree
4. Check whether the failure reproduces in other clients on the same host
   - especially OpenCode vs Codex
5. If the daemon is returning empty payloads only for `cmd=context`, inspect upstream daemon handling for the `context` command family

## Residual Uncertainty

- This pass reproduced the symptom cleanly at the MCP tool level, but did not yet capture raw daemon bytes for the failing `context` request.
- Because direct contained CLI `context` succeeds, the exact break location inside the MCP/daemon path is still not fully isolated.
- The existing local diagnostic improvements may not be surfacing through the exact tool invocation path used by this runtime.

## QA Conclusion

- The original `bd-htga` parse-error symptom is real and reproducible.
- This is a tooling/control-plane bug.
- It is not a product bug.
- The best current classification is: MCP `context` path failure with intact non-`context` llm-tldr surfaces and intact direct CLI `context`.
