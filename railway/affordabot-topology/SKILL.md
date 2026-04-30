---
name: affordabot-topology
description: |
  Affordabot Railway dev topology and safe runtime context. MUST BE USED when working in affordabot and the task needs Railway project/environment/service IDs, dev service endpoints, pgvector, MinIO, SearXNG, backend/frontend domains, or non-interactive Railway linking.
  Use for: "Affordabot Railway", "affordabot endpoints", "railway/dev", "dev topology", "pgvector-dev", "backend-dev", "bucket-dev", "searxng-private", "runtime readiness".
tags: [railway, affordabot, topology, endpoints, runtime, dx]
allowed-tools:
  - Bash(railway:*)
  - Bash(dx-load-railway-auth.sh:*)
  - Bash(~/agent-skills/scripts/dx-load-railway-auth.sh:*)
---

# Affordabot Railway Dev Topology

Use this skill before blocking on missing Affordabot Railway context. The
values below are non-secret identifiers and endpoints. Secrets and tokens stay
in 1Password/cache-backed auth and must not be copied into repos or prompts.

## Safe Auth Contract

Do not run raw `op read`, `op item get`, `op item list`, or `op whoami`.

Use the cache/service-account Railway helper:

```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami
```

## Non-Interactive Link

From an Affordabot worktree:

```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  railway project link \
    --project affordabot \
    --environment dev \
    --service backend \
    --json
```

Expected result:

- project: `affordabot`
- project id: `1ed20f8a-aeb7-4de6-a02c-8851fff50d4e`
- environment: `dev`
- environment id: `3dd8dd33-6fe2-45f9-bcde-1ecd4fae0fc8`
- linked service: `backend`
- backend service id: `1b24701c-a614-4d75-b627-3084252f14a6`

## Dev Services

| Component | Railway service | Service id | Dev endpoint / note |
| --- | --- | --- | --- |
| Frontend | `frontend` | `feb62520-d176-48b8-af26-3606f1fbd6b8` | `frontend-dev-5093.up.railway.app` |
| Backend | `backend` | `1b24701c-a614-4d75-b627-3084252f14a6` | `backend-dev-3d99.up.railway.app` |
| Postgres/pgvector | `pgvector` | `027468f6-28f0-4f3e-98b5-4641d65350f2` | `pgvector-dev-2197.up.railway.app`; volume `pgvector-volume` |
| MinIO bucket | `Bucket` | `8a67776e-87a7-42c7-b0e0-1d1d2d2a60d2` | `bucket-dev-6094.up.railway.app`; volume `bucket-volume` |
| MinIO console | `Console` | `a663a289-51d1-4fc5-8561-3d409ddb61f9` | `console-dev-97ad.up.railway.app` |
| Search | `searxng-private` | `c6642469-f5e7-42fd-ab68-cbf986e32fc3` | private service; no public domain recorded |

## Verification Commands

Use these commands for non-secret topology verification:

```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway project list --json
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway status --json
```

If a task needs live database/object-store/search access, first confirm the
task is allowed to use runtime services. Then use explicit project/environment
context; do not rely on ambient links from another repo.

## Current Known Live-Integration Gaps

The topology is known, but these may still require task-specific verification:

- pgvector extension presence in the dev database
- MinIO bucket existence and credentials
- `searxng-private` internal endpoint/env binding
- Windmill workspace resources/assets/S3Object refs

These are runtime checks, not topology-discovery blockers.
