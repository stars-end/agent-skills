---
name: opencode-dispatch
description: OpenCode-first dispatch workflow for parallel delegation. Use `opencode run` for headless jobs and `opencode serve` for shared server workflows; pair with governance harness for baseline/integrity/report gates. Trigger when user asks for parallel dispatch, throughput lane execution, or OpenCode benchmarking.
tags: [workflow, dispatch, opencode, parallel, governance, benchmark, glm5]
allowed-tools:
  - Bash
---

# opencode-dispatch

OpenCode is the default execution lane for parallel workstreams.
Use `dx-runner --provider opencode` as the governed default entrypoint.

## When To Use

- Throughput-oriented parallel waves
- Reproducible benchmark runs
- Shared server execution (`opencode serve` + attach/run clients)

## When To Use cc-glm Instead

- Critical waves requiring fallback policy
- OpenCode governance gate failure (baseline/integrity/report)
- Explicit quality/backstop routing

## Standard Commands

```bash
# Governed headless lane (canonical)
dx-runner start --provider opencode --beads bd-xxx --prompt-file /tmp/task.prompt
dx-runner check --beads bd-xxx --json

# Direct headless lane (advanced)
opencode run -m zhipuai-coding-plan/glm-5 "Implement task T1 from plan.md"

# Server lane (single host)
opencode serve --hostname 127.0.0.1 --port 4096
opencode run --attach http://127.0.0.1:4096 -m zhipuai-coding-plan/glm-5 "Implement task T2 from plan.md"
```

## Attach Mode Compatibility (bd-cbsb.19.3)

The `--attach` flag connects to a running OpenCode server. However, attach mode
requires an initialized execution context on the server side.

### Pre-Flight Probe

Before using attach mode, probe compatibility:

```bash
# Check attach compatibility
dx-runner probe-attach --url http://127.0.0.1:4096 [--json]
```

Exit codes:
- `0` - Attach mode ready
- `1` - General error (server unreachable, not healthy)
- `24` - Server healthy but lacks execution context

### Error: "No context found for instance"

This error occurs when:
1. Server is running and healthy
2. Server has no active session context initialized

**Resolution:**
1. Use headless mode instead (remove `--attach` flag)
2. Or ensure server has an initialized session before attaching

### Attach Mode Fallback Pattern

```bash
# Try attach, fall back to headless
if dx-runner probe-attach --url "$OPENCODE_URL" --json 2>/dev/null | jq -e '.status == "ok"' >/dev/null; then
    opencode run --attach "$OPENCODE_URL" -m zhipuai-coding-plan/glm-5 "$PROMPT"
else
    opencode run -m zhipuai-coding-plan/glm-5 "$PROMPT"
fi
```

## Governed Benchmark Entry Points

```bash
# Progressive gate sequence
python3 scripts/benchmarks/opencode_cc_glm/run_progressive_opencode.py \
  --required-baseline "$(git rev-parse HEAD)" \
  --reported-commit "$(git rev-parse HEAD)" \
  --branch "$(git rev-parse --abbrev-ref HEAD)"

# Governance-wrapped benchmark
python3 scripts/benchmarks/opencode_cc_glm/run_governed_benchmark.py \
  --workflows opencode_run_headless,opencode_server_http,opencode_server_attach_run \
  --model zhipuai-coding-plan/glm-5 \
  --required-baseline "$(git rev-parse HEAD)" \
  --reported-commit "$(git rev-parse HEAD)" \
  --branch "$(git rev-parse --abbrev-ref HEAD)" \
  --parallel 6
```
