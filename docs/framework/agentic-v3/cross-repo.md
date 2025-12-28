# Cross-Repo Integrity (Jules & Team Lead)

## Contract Validator
Jules-driven dependency check. When `llm-common` changes, Jules boots up downstream products (`affordabot`, `prime-radiant-ai`) in a sandbox to verify the API contract remains intact.

## Daily Janitor Cron
Automated repository hygiene driven by Jules.
- Prunes merged branches.
- Deletes stale artifacts.
- Cleans orphaned Beads merge fragments.

