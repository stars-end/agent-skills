---
name: prime-radiant-topology
description: |
  Prime Radiant AI Railway dev topology and safe runtime context. MUST BE USED when working in prime-radiant-ai and the task needs Railway project/environment/service IDs, dev service endpoints, pgvector, Postgres, MinIO, Windmill/LSP services, backend/frontend domains, or non-interactive Railway linking.
  Use for: "Prime Radiant Railway", "prime-radiant-ai endpoints", "railway/dev", "frontend-dev-f8a3", "backend-dev-6dd5", "postgres-dev-50c2", "bucket-dev-2f3a", "console-dev-f0c3", "pgvector", "lsp".
tags: [railway, prime-radiant-ai, topology, endpoints, runtime, dx]
allowed-tools:
  - Bash(railway:*)
  - Bash(dx-load-railway-auth.sh:*)
  - Bash(~/agent-skills/scripts/dx-load-railway-auth.sh:*)
---

# Prime Radiant AI Railway Dev Topology

Use this skill before blocking on missing Prime Radiant AI Railway context. The
values below are non-secret identifiers and endpoints. Secrets and tokens stay
in 1Password/cache-backed auth and must not be copied into repos or prompts.

## Safe Auth Contract

Do not run raw `op read`, `op item get`, `op item list`, or `op whoami`.

Use the cache/service-account Railway helper:

```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami
```

## Non-Interactive Link

From a Prime Radiant AI worktree:

```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  railway link \
    --project prime-radiant-ai \
    --environment dev \
    --service backend
```

Expected result:

- project: `prime-radiant-ai`
- project id: `f0875753-5125-42d4-93c5-a04818e13dc6`
- environment: `dev`
- environment id: `385fcef3-5d05-4bed-b7e4-6f35570c787c`
- linked service: `backend`
- backend service id: `49ea9e34-d3dd-41d1-9e19-c4a70833784b`

## Dev Services

| Component | Railway service | Service id | Dev endpoint / note |
| --- | --- | --- | --- |
| Frontend | `frontend` | `ec1f5dea-5bba-43e3-904b-0ce4a6bb4f86` | `frontend-dev-f8a3.up.railway.app` |
| Backend | `backend` | `49ea9e34-d3dd-41d1-9e19-c4a70833784b` | `backend-dev-6dd5.up.railway.app` |
| Postgres | `Postgres` | `72f153c7-4a29-47a2-9f51-20b961f2070e` | `postgres-dev-50c2.up.railway.app`; volume `postgres-volume` |
| pgvector | `pgvector` | `145eb8a8-5453-499d-ba40-9ec878a0bc40` | no public domain shown in dev screenshot; volume `pgvector-volume` |
| MinIO bucket | `Bucket` | `b7b9eede-719c-464c-b995-e7d870f71d78` | `bucket-dev-2f3a.up.railway.app`; volume `bucket-volume` |
| MinIO console | `Console` | `6622cf0b-c201-43dc-bc36-552a653a7167` | `console-dev-f0c3.up.railway.app` |
| Windmill LSP | `lsp` | `1b2e9d13-801e-47d6-9235-b383ba8e2571` | no public domain shown; volume `lsp-volume` |

Visible dev volume tiles from the Railway topology screenshot also include
`platform-vdlz-volume` and `platform-y3_2-volume`; treat them as observed
storage topology until a task verifies their active service binding.

## Verification Commands

Use these commands for non-secret topology verification:

```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway project list --json
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway status --json
```

If a task needs live database/object-store/search/Windmill access, first
confirm the task is allowed to use runtime services. Then use explicit
project/environment context; do not rely on ambient links from another repo.

## Current Known Live-Integration Gaps

The topology is known, but these may still require task-specific verification:

- which database service is the canonical app transactional DB for the task
- whether pgvector is used directly or through app/Windmill resource bindings
- MinIO bucket names, credentials, and object lifecycle policy
- Windmill server/worker/LSP resource bindings and workspace URLs

These are runtime checks, not topology-discovery blockers.
