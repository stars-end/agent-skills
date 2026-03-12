# Secrets Architecture Options

Date: 2026-03-12
Feature: `bd-d8f4`

## Context & Problem Statement

The current secrets architecture relies heavily on 1Password Service Accounts (`op read` / `op run`) for both local host automation and shared Railway/Slack integration logic. We recently experienced an account-wide daily limit exhaustion on the `read_write` operation (1,000 requests per day for Teams/Families tier).

The current workflow has canonical VMs (`macmini`, `epyc6`, `epyc12`, `homedesktop-wsl`) polling cron jobs and running agent orchestrators that frequently read secrets like `GITHUB_TOKEN`, `RAILWAY_API_TOKEN`, `ZAI_API_KEY`, and `SLACK_BOT_TOKEN`. 

This investigation compares several options to stabilize the architecture, reduce the dependency on 1Password in the hot path, and better utilize Railway for runtime configuration.

## Required Questions Answered

**1. Which secrets should live only in Railway runtime env versus local host automation?**
- **Railway Runtime Env**: App runtime secrets (e.g., `DATABASE_URL`, API keys for deployed services like `EODHD_CRON_SHARED_SECRET`), environment-specific toggles, internal service URLs.
- **Local Host Automation**: Only DX/dev workflow secrets (e.g., `GITHUB_TOKEN`, `ZAI_API_KEY`, `RAILWAY_API_TOKEN` for CLI access, Slack transport tokens for cron alerts).

**2. Can Railway become the primary deploy/runtime secrets plane while local automation uses a much smaller cached secret set?**
Yes. Railway environments support shared, sealed, and reference variables. We can remove 1Password from the app runtime hot path completely by relying solely on Railway injected environment variables for any deployed service, reserving 1Password exclusively for host-level DX automation. 

**3. Which option best fits a small team with multiple canonical VMs and agent-driven automation?**
A hardened 1Password approach combined with Railway-native variables for runtime is the most pragmatic fit. It minimizes the need for net-new infrastructure (like managing a Vault server) while solving the immediate bottleneck through caching.

**4. What architecture removes 1Password from hot paths without losing auditability and rotation?**
Using 1Password Connect (if self-hosted) or migrating to Doppler/Infisical (with local agents/proxies) would completely remove the 1Password cloud limit from the hot path. Alternatively, heavily caching the 1Password Service Account responses locally (already partially implemented) effectively removes the API from the hot path without losing centralized rotation management.

**5. If we stay on 1Password, what is the minimum viable architecture change to stay under quota?**
The minimum viable change is a strict local persistent cache on each host (TTL 24h) for all high-frequency tokens (Z.ai, Railway, GitHub, Slack) combined with batched reads. We have started this in `dx-auth.sh` and `dx-slack-alerts.sh`. Furthermore, ensure `macmini` and `epyc6` use separate service accounts.

**6. Is the current 1Password account tier structurally incompatible with the observed workload?**
Yes, the Teams/Families limit is 1,000 requests/day account-wide. An agent workflow executing hundreds of tasks across multiple VMs can easily exhaust this in a few hours without caching. The Business tier offers 50,000 requests/day, but caching is still structurally better.

## Comparison Matrix

| Option | Architecture | Rate Limits | Pros | Cons | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Hardened 1Password (Local Cache)** | Use `op` CLI with 24h file-based cache + batched reads (`op item get --fields`). | 1,000/day (Teams) account-wide, but cached. | No new tools; fixes immediate problem; free. | Cache invalidation complexity; risks staleness during rotation. | **GO** (Immediate stabilization) |
| **2. 1Password Connect** | Self-host 1Password Connect Server on a canonical VM or Railway. Apps query the Connect Server. | Unlimited local re-requests. | Fully bypasses Service Account limits; native 1Password solution. | Requires running and monitoring a new service container. | **NO-GO** (Too much overhead for current scale) |
| **3. 1Password SDK/Environments** | Programmatic SDK integration. | Same cloud limits as Service Accounts. | Good for code, bad for bash/cron scripts. | Doesn`t solve the limit issue without external caching. | **NO-GO** |
| **4. Railway Native Env Vars** | Use Railway for all deploy/runtime secrets. | OS env limits (~128KB). No explicit rate limits. | Zero overhead; perfectly integrated with deployed apps. | Doesn`t solve host DX automation (e.g. `gh` or `op` CLI needs). | **GO** (For runtime apps only) |
| **5. Doppler** | SaaS Secret Ops platform. Local CLI for fetching. | Dev: 240 req/min. Team: 480 req/min. | Purpose-built for this; excellent DX; fallback files avoid limits. | Vendor lock-in; requires migration of all secrets; $21/user/mo for Team. | **NO-GO** (Cost & migration overhead) |
| **6. Infisical** | Cloud or Self-hosted secret manager. | Cloud: 200 reads/min (Free). Self-hosted: No limits. | Generous limits; open-source option. | Migration effort; self-hosting requires maintenance. | **NO-GO** |
| **7. HashiCorp Vault** | Self-hosted or HCP managed secrets. | No strict API limits (resource quotas apply). | Enterprise standard; dynamic secrets. | Immense operational tax to maintain; overkill for a small team. | **NO-GO** |

## Recommendation Summary

1. **Local DX / Cron / Agent Automation:** Stick with 1Password Service Accounts but strictly enforce the 24h local persistent cache (recently added in `dx-auth.sh` and `dx-slack-alerts.sh`). Do not perform uncached `op read` calls in high-frequency cron jobs or dispatcher loops.
2. **CI / Non-interactive Workflows:** Inject secrets via GitHub Actions natively (synced periodically, manually, or via minimal `op` reads at job startup).
3. **Railway Deployment / Runtime:** Exclusively use Railway Environment Variables. Do not perform `op read` at app runtime.

---
*Sources:*
- [1Password Rate Limits](https://developer.1password.com/docs/service-accounts/rate-limits)
- [1Password Connect](https://developer.1password.com/docs/connect)
- [Doppler Rate Limits](https://docs.doppler.com/docs/rate-limits)
- [Infisical Limits](https://infisical.com/docs/documentation/platform/rate-limits)
- [HashiCorp Vault Quotas](https://developer.hashicorp.com/vault/docs/concepts/resource-quotas)
