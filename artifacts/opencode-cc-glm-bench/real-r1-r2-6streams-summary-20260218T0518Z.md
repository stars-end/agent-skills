# R1+R2 6-Stream Benchmark Summary

Runs: real-r1-ccglm-20260218T0514Z, real-r1-opencode-20260218T0514Z, real-r2-ccglm-20260218T0516Z, real-r2-opencode-20260218T0516Z

## Overall
| system | jobs | success_rate | completion_median_ms | first_output_median_ms |
| --- | --- | --- | --- | --- |
| cc-glm | 6 | 100.0% | 25176 | 22788 |
| opencode | 6 | 100.0% | 19691 | 10357 |

## By Prompt (Completion ms, R1/R2)
| prompt | cc-glm | opencode | faster_median |
| --- | --- | --- | --- |
| coding_ability_2 | 35445/24408 | 17279/22403 | opencode |
| latency_speed_1 | 12476/19168 | 45378/11222 | cc-glm |
| robustness_partial_context_1 | 25945/31786 | 20286/19097 | opencode |
