# Benchmark Summary: real-p2-latency-speed-1-20260218T0457Z

Generated: 2026-02-18T04:57:17Z
Total records: 4

## Workflow Metrics
| workflow_id | jobs | success_rate | retry_rate | startup_ms_mean | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- | --- |
| cc_glm_headless | 1 | 100.0% | 0.0% | 5 | 9121 | 11565 |
| opencode_run_headless | 1 | 0.0% | 0.0% | 8 | 1974 | 1989 |
| opencode_server_attach_run | 1 | 0.0% | 0.0% | 2 | - | 1603 |
| opencode_server_http | 1 | 100.0% | 0.0% | 0 | 1069 | 6276 |

## System Comparison
| system | jobs | success_rate | retry_rate | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- |
| cc-glm | 1 | 100.0% | 0.0% | 9121 | 11565 |
| opencode | 3 | 33.3% | 0.0% | 1522 | 1989 |

## Prompt Side-by-Side
| prompt_id | category | cc_glm_headless | opencode_run_headless | opencode_server_attach_run | opencode_server_http |
| --- | --- | --- | --- | --- | --- |
| latency_speed_1 | latency_speed | ok (11565ms) | fail:model | fail:harness | ok (6276ms) |

## Failure Taxonomy
| key | count | kind |
| --- | --- | --- |
| harness | 1 | category |
| model | 1 | category |
| empty_or_unknown | 1 | reason |
| model_not_supported | 1 | reason |
