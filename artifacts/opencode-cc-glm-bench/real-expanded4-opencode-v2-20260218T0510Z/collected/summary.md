# Benchmark Summary: real-expanded4-opencode-v2-20260218T0510Z

Generated: 2026-02-18T05:10:58Z
Total records: 12

## Workflow Metrics
| workflow_id | jobs | success_rate | retry_rate | startup_ms_mean | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- | --- |
| opencode_run_headless | 4 | 100.0% | 0.0% | 3 | 14288 | 27280 |
| opencode_server_attach_run | 4 | 100.0% | 0.0% | 1 | 6686 | 21472 |
| opencode_server_http | 4 | 100.0% | 0.0% | 0 | 478 | 30764 |

## System Comparison
| system | jobs | success_rate | retry_rate | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- |
| opencode | 12 | 100.0% | 0.0% | 6466 | 24456 |

## Prompt Side-by-Side
| prompt_id | category | opencode_run_headless | opencode_server_attach_run | opencode_server_http |
| --- | --- | --- | --- | --- |
| coding_ability_2 | coding_ability | ok (23403ms) | ok (25510ms) | ok (31558ms) |
| latency_speed_1 | latency_speed | ok (9395ms) | ok (6815ms) | ok (9059ms) |
| robustness_partial_context_1 | robustness | ok (31156ms) | ok (21796ms) | ok (32215ms) |
| workflow_orchestration_1 | workflow_orchestration | ok (33047ms) | ok (21149ms) | ok (29970ms) |

## Failure Taxonomy
| key | count | kind |
| --- | --- | --- |
| none | 0 | category |
