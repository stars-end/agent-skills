---
name: cass-memory
description: Local-first procedural/episodic memory workflow with opt-in sanitized cross-agent digest sharing.
---

# CASS Memory (Fleet Sync V2.1)

Use this skill when recurring patterns, decisions, and failure playbooks should persist across sessions.

## Contract
- Session logs remain local by default.
- Cross-agent sharing is opt-in only and must use sanitized summaries.
- Never persist raw secrets, raw transcripts, or tokens.

## Controls
- Enable sharing: `CASS_SHARE_MEMORY=1`
- Disable sharing: `CASS_NO_SHARE=1`

## Expected Output
- Local playbook updates
- Optional redacted digest records for fleet learning
