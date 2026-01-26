---
name: dx-alerts
description: Lightweight “news wire” for DX changes and breakages, posted to Slack (no MCP required).
---

# dx-alerts

Lightweight “news wire” posted to Slack, not a separate bespoke system.

Pattern:
- Publish alerts into a dedicated Slack channel/thread (recommended: a single `#dx-alerts` channel or pinned thread).
- Each alert message should start with a tag:
  - `[DX-ALERT][blocker] ...`
  - `[DX-ALERT][high] ...`
  - `[DX-ALERT][medium] ...`
  - `[DX-ALERT][low] ...`
- Include repo scope in the body (prime-radiant-ai / affordabot / llm-common) and an expiry if relevant.

Consumption:
- `dx-doctor` may optionally surface the latest N alerts (best-effort; never block).

Why:
- Avoids “agents don’t pull agent-skills” problems by pushing time-sensitive info into Slack.
