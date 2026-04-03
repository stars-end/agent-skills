# llm-tldr Codex Thread Tool-Surface Gap

CLASS: `dx_loop_control_plane`  
NOT_A_PRODUCT_BUG: `true`

## Summary

`llm-tldr` did not fail as an MCP server in this wave.

The failure was a Codex runtime exposure gap:

1. Codex config contained `llm-tldr` and `serena`
2. `codex mcp list` reported both as `enabled`
3. `tldr-mcp-contained.py` processes were alive
4. but the live thread tool surface still did not expose either tool to the model

This forced fallback to direct repo reads even though the servers were configured
and running.

## Environment

- Host: local macOS canonical host
- Runtime: Codex desktop
- App version seen in local logs: `0.118.0-alpha.2`
- Repo: `~/agent-skills`
- Config path: `~/.codex/config.toml`
- State DB: `~/.codex/state_5.sqlite`
- Log DB: `~/.codex/logs_1.sqlite`

## Exact Observed Behavior

### Codex config has the MCP servers

`~/.codex/config.toml` contains:

- `[mcp_servers."llm-tldr"]`
- `[mcp_servers."serena"]`

### Codex CLI says both are enabled

`codex mcp list` returned:

- `llm-tldr ... enabled`
- `serena ... enabled`

### Server processes are alive

Process list showed active `tldr-mcp-contained.py` processes.

### But Codex thread state shows no MCP tool exposure

`~/.codex/state_5.sqlite` currently reports:

```sql
select distinct name from thread_dynamic_tools order by name;
```

Result:

- `read_thread_terminal`

No `llm-tldr`.  
No `serena`.

And:

```sql
select count(*) from thread_dynamic_tools where name in ('llm-tldr','serena');
```

Result:

- `0`

For recent `cwd=/Users/fengning/agent-skills` threads, joined dynamic-tool
names were empty or absent.

## Expected Behavior

If Codex desktop has:

1. MCP config entries present
2. `codex mcp list` reports those tools as enabled
3. backing server processes are alive

then the live thread presented to the model should expose those tools, or the
runtime should fail loudly and precisely.

## Fault Boundary

This does **not** look like:

- `llm-tldr` daemon failure
- bad launcher config
- missing `llm-tldr` install
- missing Codex MCP config

It does look like:

- Codex desktop thread/tool hydration failure
- or an MCP-to-thread exposure gap inside Codex runtime state

The strongest local evidence is:

- `codex mcp list`: pass
- server process presence: pass
- `thread_dynamic_tools`: missing `llm-tldr` and `serena`

Likely fault boundary:

`configured + running MCP server` -> `Codex thread dynamic tool registration`

## Impact

- semantic/static-discovery tools unavailable to the model
- repeated fallback to direct file reads
- misleading health signal because `codex mcp list` appears healthy
- founder-facing investigation/review work can silently degrade

## Reproduction Commands

```bash
codex mcp list
ps aux | rg 'tldr-mcp-contained|tldr-contained-daemon|codex'
sqlite3 ~/.codex/state_5.sqlite "select distinct name from thread_dynamic_tools order by name;"
sqlite3 ~/.codex/state_5.sqlite "select count(*) from thread_dynamic_tools where name in ('llm-tldr','serena');"
sqlite3 ~/.codex/state_5.sqlite "select t.id, datetime(t.updated_at,'unixepoch','localtime'), t.cwd, group_concat(d.name, ',') from threads t left join thread_dynamic_tools d on d.thread_id=t.id where t.cwd='/Users/fengning/agent-skills' group by t.id order by t.updated_at desc limit 10;"
```

## Workaround Used

- fall back to direct repo inspection
- treat the issue as a runtime/tooling failure, not a product signal

## Proposed Fix

### Immediate local mitigation

Add a Codex-specific thread-surface check to local DX tooling:

1. keep existing `codex mcp list` preflight
2. add a second check against `~/.codex/state_5.sqlite`
3. if recent thread state for the current workspace lacks `llm-tldr` / `serena`,
   fail `dx-check` and warn in `mcp-doctor`

This does not repair Codex itself, but it prevents false-green MCP health.

### Upstream/runtime fix to pursue

Codex desktop should:

1. hydrate MCP tools into thread dynamic tool state at thread start, or
2. fail loudly when server enablement succeeds but thread tool registration does not

Concretely:

- if `codex mcp list` reports enabled tools but `thread_dynamic_tools` is missing
  them, the runtime should expose a diagnostic rather than silently degrading

## Residual Uncertainty

- We do not yet know whether this is:
  - all Codex desktop threads
  - only some thread creation paths
  - only this app build
- local logs did not surface a clear human-readable MCP registration error

## Recommendation

1. Land the local guardrail in `dx-check` + `mcp-doctor`
2. Escalate the runtime/tool-surface gap upstream with the evidence above
3. Stop treating `codex mcp list` alone as sufficient proof of Codex MCP usability
