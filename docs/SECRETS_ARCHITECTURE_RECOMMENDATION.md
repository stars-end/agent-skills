# Secrets Architecture Recommendation

**Date:** 2026-03-12
**Status:** Accepted
**Context:** Account-wide 1Password daily limit exhaustion (1,000 req/day) due to un-cached reads in agent/cron workflows.

## Target Architecture

We are adopting a **Hybrid Secrets Architecture**:
1. **Host-Level DX & Automation**: Hardened 1Password Service Accounts with mandatory 24h local caching.
2. **Deployment & Runtime**: Railway Native Environment Variables.

### Phase 1: Immediate Stabilization (Current)
- Enforce the `dx-auth.sh` and `dx-slack-alerts.sh` local file cache for high-frequency tokens (`ZAI_API_KEY`, `RAILWAY_API_TOKEN`, `GITHUB_TOKEN`, Slack tokens).
- Remove all direct, un-cached `op read` calls from cron jobs, adapters (`cc-glm.sh`), and health probes.
- Ensure `macmini` and `epyc6` do not share the exact same service-account token (regenerate and assign distinct tokens).

### Phase 2: Medium-Term Migration
- Audit all remaining `op read` calls in `agent-skills` and other repositories.
- Route any remaining host-level auth through `dx_auth_read_secret_cached` (from `dx-auth.sh`).
- Migrate any deployed apps that currently fetch secrets at runtime via `op` to use Railway-native environment variables.

### Phase 3: Long-Term Steady State
- Railway remains the sole source of truth for runtime secrets.
- 1Password remains the source of truth for developer access, API keys, and infrastructure bootstrap.
- If the 1,000 req/day limit is repeatedly hit despite strict caching, upgrade the 1Password account to Business (50,000 req/day) rather than migrating to Doppler/Infisical, as the migration effort outweighs the subscription cost.

## Rejected Alternatives
- **1Password Connect / HashiCorp Vault / Infisical (Self-Hosted)**: Rejected due to the operational overhead of maintaining a highly available secret proxy/server for a small team.
- **Doppler / Infisical (Cloud)**: Rejected due to the migration cost and vendor switch. 1Password with caching is sufficient.

## Implementation Rules
- **No `op read` in app code.** Deployed services must rely on their Railway environment.
- **No `op read` in tight loops.** Automation scripts must use the cached wrappers in `~/agent-skills/scripts/lib/dx-auth.sh`.
