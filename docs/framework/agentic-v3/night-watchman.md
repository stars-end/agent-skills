# The Night Watchman (Autonomous QA)

A proactive, domain-aware agent that hunts for logical and visual regressions.

## Domain-Aware Architecture
The agent is primed with repo-specific knowledge to distinguish between UI polish and critical business logic failures.

### Knowledge Root: `docs/domain/context.md`
Defines the 'Ground Truth' for the product:
- **Affordabot:** Accuracy of cost-of-living metrics, citation validity.
- **Prime Radiant:** Fintech compliance, data precision (Sharpe, Beta), brokerage sync reliability.

### Persona Matrix: `docs/personas/*.md`
Simulates real users to find 'Unknown Unknowns':
- `Cautious Cathy`: Retail investor sensitive to risk/clarity.
- `Legislator Larry`: Policy maker requiring high-level summaries and evidence.

## Remediation Loop
1. **Find:** Vision-based exploration finds a bug.
2. **Analyze:** GLM-4.7 categorizes bug and generates a fix (patch).
3. **Dispatch:** Night Watchman auto-dispatches a **Jules** session to apply and verify the fix.

