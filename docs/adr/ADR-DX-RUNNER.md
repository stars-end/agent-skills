# ADR: Unified Runner (dx-runner)

## Status
ACCEPTED - 2026-02-18

## Context

The current dispatch landscape has overlapping execution planes:
- `cc-glm-job.sh`: Proven job management with governance gates
- `dx-dispatch` + `lib/fleet`: Python-based dispatcher with backend abstraction
- Various SSH wrapper scripts
- Benchmark harnesses with their own preflight logic

This creates:
1. **Drift**: Preflight/no-op logic duplicated across scripts
2. **Confusion**: Multiple entry points for similar tasks
3. **Maintenance burden**: Fixes must be applied in multiple places
4. **Observability gaps**: Different logging/metadata formats

## Decision

Replace overlapping dispatch planes with ONE canonical lean runner (`dx-runner`) routing to 3 providers:
- `cc-glm`: Claude via Z.ai (proven reliability backstop)
- `opencode`: OpenCode headless (primary throughput lane)
- `gemini`: Gemini CLI (future capacity)

### Architecture

```
                    ┌──────────────────────────────────────┐
                    │           dx-runner                   │
                    │  (single command surface)             │
                    │                                       │
                    │  start/status/check/restart/stop/     │
                    │  watchdog/report/preflight            │
                    │                                       │
                    │  [shared governance layer]            │
                    │  - preflight                          │
                    │  - permission (worktree-only)         │
                    │  - no-op heartbeat detection          │
                    │  - baseline/integrity/feature-key     │
                    └──────────────┬───────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
       ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
       │ cc-glm      │     │ opencode    │     │ gemini      │
       │ adapter     │     │ adapter     │     │ adapter     │
       └─────────────┘     └─────────────┘     └─────────────┘
```

### Adapter Contract

All providers implement the same interface:

```bash
# Required adapter functions (sourced or exec'd):
adapter_start()       # Start a job
adapter_check()       # Check health state
adapter_stop()        # Stop a job
adapter_preflight()   # Provider-specific preflight
adapter_probe_model() # Test model availability
```

### Shared Governance (Unified Implementation)

1. **Preflight**: Auth, model, backend reachability
2. **Permission Gate**: Worktree-only path policy (fixes bd-cbsb.16)
3. **No-op Heartbeat**: Tool-invocation/mutation tracking (fixes bd-cbsb.17)
4. **Baseline Gate**: Runtime commit verification
5. **Integrity Gate**: Reported commit verification
6. **Feature-Key Gate**: Commit trailer verification
7. **Failure Taxonomy**: Deterministic classification

### Command Surface

```bash
dx-runner start --beads <id> --provider <cc-glm|opencode|gemini> --prompt-file <path> [options]
dx-runner status [--beads <id>] [--json]
dx-runner check --beads <id> [--json]
dx-runner restart --beads <id>
dx-runner stop --beads <id>
dx-runner watchdog [--interval <sec>] [--max-retries <n>]
dx-runner report --beads <id> [--format json|markdown]
dx-runner preflight [--provider <name>]
dx-runner probe --provider <name> --model <id>
```

## Consequences

### Positive
- Single source of truth for dispatch logic
- Unified governance ensures consistent behavior
- Provider differences are isolated to adapters
- Simplified operator experience
- Deterministic JSON output for automation

### Negative
- Migration effort for existing workflows
- Adapter implementation required for new providers

### Mitigations
- `dx-dispatch` becomes compat shim forwarding to `dx-runner`
- Existing `cc-glm-job.sh` continues to work (calls into `dx-runner`)
- Comprehensive test suite before cutover

## Implementation Notes

1. **Reuse, don't rewrite**: Extract proven logic from `cc-glm-job.sh`
2. **Provider-specific behavior**: Adapter-only, no core changes
3. **Machine-readable outputs**: Stable JSON schema
4. **Deterministic substates**: No ambiguous running/empty states

## Related
- bd-xga8.14: Epic for unified runner implementation
- bd-cbsb.14-.18: Bugs this architecture resolves
- OpenCode CLI: https://opencode.ai/docs/cli/
- OpenCode server: https://opencode.ai/docs/server/
