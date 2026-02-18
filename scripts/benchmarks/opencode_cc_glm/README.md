# OpenCode/cc-glm Benchmark Harness

## Lane policy

- Primary throughput lane: OpenCode (`opencode run`, `opencode serve`)
- Reliability/quality fallback lane: cc-glm (`cc-glm-job.sh` / `cc_glm_headless`)
- Switch to cc-glm when OpenCode fails governance gates or critical-wave policy requires fallback

## Progressive OpenCode-first flow

1. Phase 1 smoke:
```bash
scripts/benchmarks/opencode_cc_glm/run_progressive_opencode.py --phase phase1_smoke
```

2. Phase 2 throughput (6 streams):
```bash
scripts/benchmarks/opencode_cc_glm/run_progressive_opencode.py --phase phase2_6stream
```

3. Phase 3 real coding gate:
```bash
scripts/benchmarks/opencode_cc_glm/run_progressive_opencode.py --phase phase3_real_coding_gate
```

Phase gating is enforced via:
`artifacts/opencode-cc-glm-bench/progressive/state.json`

Optional governance gates:
```bash
# Pre-dispatch runtime baseline gate
scripts/benchmarks/opencode_cc_glm/run_progressive_opencode.py \
  --phase phase2_6stream \
  --required-baseline 40ffdc4

# Post-wave integrity gate (reported commit must be ancestor of branch head)
scripts/benchmarks/opencode_cc_glm/run_progressive_opencode.py \
  --phase phase3_real_coding_gate \
  --reported-commit <sha> \
  --branch feature-bd-cbsb
```

Provider-agnostic governed wave runner:
```bash
scripts/benchmarks/opencode_cc_glm/run_governed_benchmark.py \
  --workflows opencode_run_headless,opencode_server_http,opencode_server_attach_run,cc_glm_headless \
  --model zai-coding-plan/glm-5 \
  --required-baseline <sha> \
  --reported-commit <sha> \
  --branch feature-bd-cbsb
```

`run_governed_benchmark.py` always attempts collection/summary even if launcher returns non-zero, so partial failures still produce machine-readable taxonomy and governance reports.

Deferred DX v8.x residual fix integration should begin only after `phase3_real_coding_gate` passes.
