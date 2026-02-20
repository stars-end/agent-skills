# Benchmark Summary: real-r1-gemini-20260218T0522Z

Generated: 2026-02-18T05:29:55Z
Total records: 3

## Workflow Metrics
| workflow_id | jobs | success_rate | retry_rate | startup_ms_mean | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- | --- |
| gemini_run_headless | 3 | 66.7% | 0.0% | 6 | 7606 | 15147 |

## System Comparison
| system | jobs | success_rate | retry_rate | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- |
| gemini | 3 | 66.7% | 0.0% | 7606 | 15147 |

## Prompt Side-by-Side
| prompt_id | category | gemini_run_headless |
| --- | --- | --- |
| coding_ability_2 | coding_ability | fail:env |
| latency_speed_1 | latency_speed | ok (15147ms) |
| robustness_partial_context_1 | robustness | ok (31022ms) |

## Failure Taxonomy
| key | count | kind |
| --- | --- | --- |
| env | 1 | category |
| quota_or_rate_limit | 1 | reason |
