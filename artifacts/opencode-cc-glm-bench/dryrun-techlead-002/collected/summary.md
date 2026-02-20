# Benchmark Summary: dryrun-techlead-002

Generated: 2026-02-18T04:42:27Z
Total records: 20

## Workflow Metrics
| workflow_id | jobs | success_rate | retry_rate | startup_ms_mean | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- | --- |
| cc_glm_headless | 5 | 100.0% | 40.0% | 56 | 352 | 2101 |
| opencode_run_headless | 5 | 100.0% | 40.0% | 71 | 590 | 2272 |
| opencode_server_attach_run | 5 | 100.0% | 20.0% | 74 | 420 | 2123 |
| opencode_server_http | 5 | 100.0% | 20.0% | 69 | 742 | 2148 |

## System Comparison
| system | jobs | success_rate | retry_rate | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- |
| cc-glm | 5 | 100.0% | 40.0% | 352 | 2101 |
| opencode | 15 | 100.0% | 26.7% | 590 | 2148 |

## Prompt Side-by-Side
| prompt_id | category | cc_glm_headless | opencode_run_headless | opencode_server_attach_run | opencode_server_http |
| --- | --- | --- | --- | --- | --- |
| coding_ability_1 | coding_ability | ok (2472ms) | ok (1520ms) | ok (1760ms) | ok (2897ms) |
| coding_ability_2 | coding_ability | ok (1646ms) | ok (2395ms) | ok (2170ms) | ok (1586ms) |
| latency_speed_1 | latency_speed | ok (2697ms) | ok (2280ms) | ok (2123ms) | ok (2092ms) |
| robustness_partial_context_1 | robustness | ok (793ms) | ok (1290ms) | ok (1576ms) | ok (2148ms) |
| workflow_orchestration_1 | workflow_orchestration | ok (2101ms) | ok (2272ms) | ok (2163ms) | ok (2464ms) |

## Failure Taxonomy
| key | count | kind |
| --- | --- | --- |
| none | 0 | category |
