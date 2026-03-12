# 1Password Service-Account Usage Inventory

Date: 2026-03-12
Feature: `bd-d8f4`

## Verified limit state

- `op service-account ratelimit --format json` shows:
- Per-token hourly reads: unused (`used=0`, `remaining=1000`)
- Account-wide daily limit: exhausted (`used=1000`, `remaining=0`)
- Scope is account-wide, not a single token.

## Host identity findings

- `macmini` and `epyc6` share the same service-account token contents and `user_uuid`.
- `epyc12` and `homedesktop-wsl` use different service-account identities.
- All three distinct service-account identities fail the same `op item get Agent-Secrets-Production --vault dev --format json` call once the account-wide daily limit is exhausted.

## Repo-wide direct 1Password call sites

Highest-count files by direct `op` usage in `scripts/`:

1. `scripts/lib/dx-slack-alerts.sh`
2. `scripts/adapters/cc-glm.sh`
3. `scripts/lib/dx-auth.sh`
4. `scripts/dx-fleet-check.sh`
5. `scripts/founder-briefing-cron.sh`

Interpretation:

- `dx-slack-alerts.sh` is the shared Slack transport path. It is already patched to use a 24h local cache and a single item fetch instead of multiple field reads.
- `dx-auth.sh` is the shared Railway/secret hydration path and is the best place to reduce repetitive reads.
- `cc-glm.sh` can be high-volume if preflight/probe flows are run repeatedly during dispatch or health checks.
- `founder-briefing-cron.sh` had a direct uncached `GITHUB_TOKEN` read.
- `dx-fleet-check.sh` weekly Railway auth had a direct uncached `RAILWAY_API_TOKEN` read.

## Host-wide scheduled automation inventory

Observed recurring schedules:

- `macmini`
  - High cron density via `dx-job-wrapper.sh`
  - `dx-audit-cron.sh --daily`
  - `founder-briefing-cron.sh`
  - `dx-heartbeat-cron.sh`
  - multiple fetch/reconcile/nightly dispatcher jobs
- `epyc6`
  - canonical-evacuate every 15 minutes during active hours
  - daily/weekly fleet audit
- `epyc12`
  - canonical-evacuate every 15 minutes during active hours
  - daily/weekly fleet audit
- `homedesktop-wsl`
  - canonical-evacuate every 15 minutes during active hours

Important nuance:

- Most cron entries go through `dx-job-wrapper.sh`, which sources the Slack helper but does not itself perform `op read`.
- Transport secret reads only happen when a message send path is exercised and cache is absent/stale.
- Based on repo inspection alone, the visible `agent-skills` cron surface does not plausibly explain a persistent account-wide exhaustion by itself.

## Ranked likely in-repo consumers

1. `cc-glm` auth resolution and model probe flows
2. shared Railway token hydration via `dx-auth.sh` / `dx-load-railway-auth.sh` / `dx-railway-run.sh`
3. Slack transport bootstrap when cache is cold or missing
4. founder briefing GitHub token hydration
5. weekly fleet Railway auth check

## Patches applied in this branch

1. Add shared 24h local secret cache in `scripts/lib/dx-auth.sh`
2. Route `RAILWAY_API_TOKEN` hydration through the shared cache
3. Route `GITHUB_TOKEN` hydration through the shared cache
4. Route `ZAI_API_KEY` hydration through the shared cache
5. Remove direct uncached `op read` calls from:
   - `scripts/founder-briefing-cron.sh`
   - `scripts/dx-fleet-check.sh`
   - `scripts/adapters/cc-glm.sh`

## Remaining likely sources outside this repo

- other local repos or dotfile automation using the same 1Password account
- external services, scripts, or agents running outside `agent-skills`
- manual CLI usage loops or non-repo automation on any host

## Recommended next step

- Build a whole-account service-account consumer inventory across all canonical hosts and all active repos, not just `agent-skills`.
