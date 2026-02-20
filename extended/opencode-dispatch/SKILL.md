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

## Model Policy

- OpenCode canonical model is `zhipuai-coding-plan/glm-5`.
- `dx-runner` OpenCode adapter enforces this model strictly.
- If unavailable, fail fast and route to `cc-glm` or `gemini`.
