# OpenCode vs cc-glm (glm-5) Reproducible Benchmark Plan

## Goal
Build a reproducible harness to compare OpenCode as a parallel delegation path against `cc-glm` with `glm-5` as baseline.

## References
- Local CLI help: `opencode --help`, `opencode run --help`, `opencode serve --help`
- Server API docs: https://opencode.ai/docs/server/

## Scope
- Same 5 prompts run across both systems.
- 4 workflows (2 headless + 2 server mode).
- Deterministic run metadata and machine-readable outputs.
- Failure taxonomy: `harness`, `model`, `env`.

## Workflows
1. `cc_glm_headless`
- Path: `extended/cc-glm/scripts/cc-glm-headless.sh`
- Model pin: `CC_GLM_MODEL=glm-5`
- Execution: one prompt per isolated process

2. `opencode_run_headless`
- Path: `opencode run --format json --model zhipuai-coding-plan/glm-5`
- Execution: one prompt per isolated process

3. `opencode_server_http`
- Path: `opencode serve` + HTTP API
- Session flow: `POST /session` -> `POST /session/:id/prompt_async` -> poll `/session/status` + `/session/:id/message`
- Model handling: enforce `model=zhipuai-coding-plan/glm-5`; if unavailable, classify as `model` and route to fallback provider

4. `opencode_server_attach_run`
- Path: `opencode serve` + client attach mode
- Execution: `opencode run --attach http://HOST:PORT --format json --model zhipuai-coding-plan/glm-5`

## Parallel Strategy
- Global queue across all prompts/workflows.
- Configurable parallelism (`--parallel N`).
- Retry policy (`--max-retries`, default 1).
- Per-job tags: `run_id`, `workflow_id`, `prompt_id`.

## Metrics
Per job:
- `startup_latency_ms`: process spawn overhead (or server bootstrap for server workflows)
- `first_output_latency_ms`: submit -> first observable output
- `completion_latency_ms`: submit -> completion
- `success` and `retry_count`
- `failure_category`: `harness | model | env`

Aggregates:
- success rate
- retry rate
- p50/p95 first-output latency
- p50/p95 completion latency
- side-by-side prompt status table across workflows

## Determinism and Logging Constraints
- Prompt set is fixed in `benchmark_prompts.json`.
- `run_id` is explicit (or timestamp-derived) and used in file names.
- Logs are sanitized for secret-like patterns (`op://`, bearer tokens, key-like strings).
- No environment dumps in artifacts.

## Failure Taxonomy
- `harness`: script/collector/summarizer/runtime orchestration failures
- `model`: non-zero model runs, malformed outputs, timeout-at-model level
- `env`: missing CLI, auth/provider not configured, connection/network/server unavailable

## Files and Outputs
Inputs:
- `scripts/benchmarks/opencode_cc_glm/benchmark_prompts.json`

Executables:
- `scripts/benchmarks/opencode_cc_glm/launch_parallel_jobs.py`
- `scripts/benchmarks/opencode_cc_glm/collect_results.py`
- `scripts/benchmarks/opencode_cc_glm/summarize_results.py`

Outputs per run:
- `artifacts/opencode-cc-glm-bench/<run_id>/manifest.json`
- `artifacts/opencode-cc-glm-bench/<run_id>/raw/*.json`
- `artifacts/opencode-cc-glm-bench/<run_id>/run_results.json`
- `artifacts/opencode-cc-glm-bench/<run_id>/collected/results.json`
- `artifacts/opencode-cc-glm-bench/<run_id>/collected/records.ndjson`
- `artifacts/opencode-cc-glm-bench/<run_id>/collected/summary.md`
- `artifacts/opencode-cc-glm-bench/<run_id>/collected/summary.json`

## Run Commands
Full benchmark (real run):
```bash
RUN_ID="bench-$(date -u +%Y%m%dT%H%M%SZ)"
python3 scripts/benchmarks/opencode_cc_glm/launch_parallel_jobs.py \
  --run-id "$RUN_ID" \
  --prompts-file scripts/benchmarks/opencode_cc_glm/benchmark_prompts.json \
  --workflows cc_glm_headless,opencode_run_headless,opencode_server_http,opencode_server_attach_run \
  --parallel 4 \
  --model zhipuai-coding-plan/glm-5 \
  --max-retries 1
python3 scripts/benchmarks/opencode_cc_glm/collect_results.py \
  --run-dir "artifacts/opencode-cc-glm-bench/$RUN_ID"
python3 scripts/benchmarks/opencode_cc_glm/summarize_results.py \
  --results-json "artifacts/opencode-cc-glm-bench/$RUN_ID/collected/results.json"
```

Dry run (deterministic smoke test):
```bash
RUN_ID="dryrun-$(date -u +%Y%m%dT%H%M%SZ)"
python3 scripts/benchmarks/opencode_cc_glm/launch_parallel_jobs.py \
  --run-id "$RUN_ID" \
  --prompts-file scripts/benchmarks/opencode_cc_glm/benchmark_prompts.json \
  --workflows cc_glm_headless,opencode_run_headless,opencode_server_http,opencode_server_attach_run \
  --parallel 4 \
  --model zhipuai-coding-plan/glm-5 \
  --max-retries 1 \
  --dry-run
python3 scripts/benchmarks/opencode_cc_glm/collect_results.py \
  --run-dir "artifacts/opencode-cc-glm-bench/$RUN_ID"
python3 scripts/benchmarks/opencode_cc_glm/summarize_results.py \
  --results-json "artifacts/opencode-cc-glm-bench/$RUN_ID/collected/results.json"
```
