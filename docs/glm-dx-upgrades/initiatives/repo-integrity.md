# Repo-Integrity Sentinel (GLM-4.7)

Solving the 'Shadow Toil' of infrastructure desync.

### Capabilities
- **Schema Awareness:** Proposes SQL/SQLAlchemy fixes when DB contract drifts.
- **Lockfile Repair:** Automatically runs `poetry lock` or `pnpm install` when desync is detected.
- **Submodule Staleness:** Fixes `llm-common` pointer drift.

---

# Automated Mock Generator (Jules)

Reducing the manual overhead of test maintenance.

### Workflow
1. Detect interface change in `llm-common`.
2. Jules scans all product repos for `AsyncMock` or `patch` usages of that interface.
3. Jules generates a commit to update the mocks to the new signature.

