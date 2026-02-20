# Benchmark Summary: dryrun-techlead-001

Generated: 2026-02-18T04:41:37Z
Total records: 20

## Workflow Metrics
| workflow_id | jobs | success_rate | retry_rate | startup_ms_mean | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- | --- |
| cc_glm_headless | 5 | 100.0% | 0.0% | 60 | 488 | 2234 |
| opencode_run_headless | 5 | 100.0% | 20.0% | 71 | 482 | 947 |
| opencode_server_attach_run | 5 | 100.0% | 20.0% | 69 | 766 | 2179 |
| opencode_server_http | 5 | 100.0% | 0.0% | 54 | 486 | 2268 |

## System Comparison
| system | jobs | success_rate | retry_rate | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- |
| cc-glm | 5 | 100.0% | 0.0% | 488 | 2234 |
| opencode | 15 | 100.0% | 13.3% | 568 | 2003 |

## Prompt Side-by-Side
| prompt_id | category | cc_glm_headless | opencode_run_headless | opencode_server_attach_run | opencode_server_http |
| --- | --- | --- | --- | --- | --- |
| coding_ability_1 | coding_ability | ok (1264ms) | ok (944ms) | ok (2179ms) | ok (2268ms) |
| coding_ability_2 | coding_ability | ok (1401ms) | ok (947ms) | ok (1367ms) | ok (2660ms) |
| latency_speed_1 | latency_speed | ok (2253ms) | ok (816ms) | ok (2783ms) | ok (2003ms) |
| robustness_partial_context_1 | robustness | ok (2270ms) | ok (1873ms) | ok (2196ms) | ok (881ms) |
| workflow_orchestration_1 | workflow_orchestration | ok (2234ms) | ok (2506ms) | ok (1282ms) | ok (2400ms) |

## Failure Taxonomy
| key | count | kind |
| --- | --- | --- |
| none | 0 | category |
