# Benchmark Summary: real-p1-coding-ability-1c-20260218T0455Z

Generated: 2026-02-18T04:56:31Z
Total records: 4

## Workflow Metrics
| workflow_id | jobs | success_rate | retry_rate | startup_ms_mean | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- | --- |
| cc_glm_headless | 1 | 0.0% | 0.0% | 2 | - | 90074 |
| opencode_run_headless | 1 | 0.0% | 0.0% | 4 | 1755 | 1770 |
| opencode_server_attach_run | 1 | 0.0% | 0.0% | 3 | - | 1515 |
| opencode_server_http | 1 | 100.0% | 0.0% | 0 | 1252 | 88471 |

## System Comparison
| system | jobs | success_rate | retry_rate | first_output_ms_p50 | completion_ms_p50 |
| --- | --- | --- | --- | --- | --- |
| cc-glm | 1 | 0.0% | 0.0% | - | 90074 |
| opencode | 3 | 33.3% | 0.0% | 1504 | 1770 |

## Prompt Side-by-Side
| prompt_id | category | cc_glm_headless | opencode_run_headless | opencode_server_attach_run | opencode_server_http |
| --- | --- | --- | --- | --- | --- |
| coding_ability_1 | coding_ability | fail:model | fail:model | fail:harness | ok (88471ms) |

## Failure Taxonomy
| key | count | kind |
| --- | --- | --- |
| harness | 1 | category |
| model | 2 | category |
| empty_or_unknown | 1 | reason |
| model_not_supported | 1 | reason |
| timeout | 1 | reason |
