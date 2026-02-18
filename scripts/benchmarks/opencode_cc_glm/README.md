# OpenCode/cc-glm Benchmark Harness

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
  --workflows opencode_run_headless,cc_glm_headless \
  --model zai-coding-plan/glm-5 \
  --required-baseline <sha> \
  --reported-commit <sha> \
  --branch feature-bd-cbsb
```

Deferred DX v8.x residual fix integration should begin only after `phase3_real_coding_gate` passes.
