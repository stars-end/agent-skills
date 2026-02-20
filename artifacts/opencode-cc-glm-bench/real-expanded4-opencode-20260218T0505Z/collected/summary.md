# Benchmark Summary: real-expanded4-opencode-20260218T0505Z

Generated: 2026-02-18T05:06:49Z
Total records: 12

## Workflow Metrics
| workflow_id | jobs | success_rate | retry_rate | startup_ms_mean | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- | --- |
| opencode_run_headless | 4 | 100.0% | 0.0% | 2 | 9737 | 19494 |
| opencode_server_attach_run | 4 | 100.0% | 0.0% | 2 | 5910 | 18100 |
| opencode_server_http | 4 | 100.0% | 0.0% | 0 | 574 | 15798 |

## System Comparison
| system | jobs | success_rate | retry_rate | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- |
| opencode | 12 | 100.0% | 0.0% | 5910 | 17234 |

## Prompt Side-by-Side
| prompt_id | category | opencode_run_headless | opencode_server_attach_run | opencode_server_http |
| --- | --- | --- | --- | --- |
| coding_ability_2 | coding_ability | ok (21384ms) | ok (22283ms) | ok (16864ms) |
| latency_speed_1 | latency_speed | ok (9731ms) | ok (6818ms) | ok (7207ms) |
| robustness_partial_context_1 | robustness | ok (28534ms) | ok (39233ms) | ok (14732ms) |
| workflow_orchestration_1 | workflow_orchestration | ok (17604ms) | ok (13917ms) | ok (20488ms) |

## Failure Taxonomy
| key | count | kind |
| --- | --- | --- |
| none | 0 | category |
