## Reviewer Output Schema

End every review response with this block so `dx-review summarize` can parse results consistently.

```text
VERDICT: pass|pass_with_findings|fail|blocked
SUMMARY: <one concise paragraph>
FINDINGS_COUNT: <integer>
FINDINGS:
- [SEV=<high|medium|low>] <title> :: <impact and evidence>
- [SEV=<high|medium|low>] <title> :: <impact and evidence>
EVIDENCE:
- <commands inspected, files reviewed, key outputs>
USAGE:
- input_tokens: <number|unavailable>
- output_tokens: <number|unavailable>
- total_tokens: <number|unavailable>
- estimated_cost_usd: <number|unavailable>
READ_ONLY_ENFORCEMENT: provider_enforced|contract_only|unavailable
```

Rules:
- Keep findings grounded in inspected evidence.
- If there are no findings, set `FINDINGS_COUNT: 0` and use `VERDICT: pass`.
- Use `blocked` only when required review evidence cannot be obtained.
