# The Night Watchman: Autonomous QA Agent

An overnight 'Chaos Monkey' that uses GLM-4.6v and GLM-4.7 to find and remediate regressions on master.

## Workflow (2 AM Daily)

1.  **Context Building (GLM-4.7):**
    - Scans git log for the last 24 hours.
    - Identifies 'Changed Areas' (e.g., 'Analytics Dashboard', 'Brokerage Auth').
2.  **Exploration (GLM-4.6v):**
    - Spawns Playwright on master deployment.
    - **Mission:** 'Explore the changed areas. Look for visual breakage, NaN values, or dead ends.'
    - Captures evidence: Screenshots + Network Logs.
3.  **Synthesis (GLM-4.7):**
    - Evaluates evidence.
    - **Classification:**
        - **Fixable Bug:** Generates a Beads task + detailed patch.
        - **Systemic Issue:** Generates a PRD/Alert for Human review.
4.  **Remediation:**
    - **Auto-Dispatch:** If it's a clear code bug, it dispatches a Jules session (`jules-ready` label) to apply the fix and verify.

## Communication
- Produces a **'Morning Briefing'** report in `docs/nightly-audit/YYYY-MM-DD.md`.
- Posts to GitHub Discussion or beads-slack if a P0 is found.

