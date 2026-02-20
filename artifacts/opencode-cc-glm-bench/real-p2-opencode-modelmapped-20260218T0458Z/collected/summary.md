# Benchmark Summary: real-p2-opencode-modelmapped-20260218T0458Z

Generated: 2026-02-18T04:58:30Z
Total records: 2

## Workflow Metrics
| workflow_id | jobs | success_rate | retry_rate | startup_ms_mean | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- | --- |
| opencode_run_headless | 1 | 100.0% | 0.0% | 2 | 6616 | 7954 |
| opencode_server_attach_run | 1 | 100.0% | 0.0% | 1 | 8601 | 11129 |

## System Comparison
| system | jobs | success_rate | retry_rate | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- |
| opencode | 2 | 100.0% | 0.0% | 7608 | 9542 |

## Prompt Side-by-Side
| prompt_id | category | opencode_run_headless | opencode_server_attach_run |
| --- | --- | --- | --- |
| latency_speed_1 | latency_speed | ok (7954ms) | ok (11129ms) |

## Failure Taxonomy
| key | count | kind |
| --- | --- | --- |
| none | 0 | category |
