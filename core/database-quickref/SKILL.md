---
name: database-quickref
description: Fail-fast quick reference for Railway Postgres operations. Use when user asks to check database, run queries, verify data, inspect tables, or mentions psql, postgres, database, "check the db", "validate data".
tags: [database, postgres, railway, psql]
allowed-tools:
  - Bash(railway:*)
  - Bash(psql)
  - Read
---

# Database Quick Reference

Railway Postgres quick reference for database operations with strict preflight and blocker rules.

## Purpose

Fast access to Railway Postgres without digging through docs or remembering service names.

## When to Use This Skill

**Trigger phrases:**
- "check the database"
- "run a query"
- "inspect the db"
- "validate data"
- "connect to postgres"
- "psql into..."

**Use when:**
- Debugging data issues
- Verifying schema changes
- Running ad-hoc queries
- Checking table contents

## Preflight First

Before any DB action:

1. Load auth in the same invocation:
```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami
```
2. For Prime Radiant AI, prefer the host-safe Postgres wrapper first:
```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc 'cd backend && poetry run python scripts/db_inspect.py tables'
```
3. Check whether host `psql` exists:
```bash
command -v psql
```
4. Prefer `dx-railway-postgres.sh` for DB operations and `railway run -p/-e/-s -- ...` for non-DB Railway execution.

If `psql` is missing and there is no verified repo-native query path already present, stop exactly with:

```text
BLOCKED: no_sql_client_and_no_verified_query_runtime
NEEDS: approved DB query path or provisioned client/runtime
NEXT_COMMANDS:
1) verify an existing repo-native query runner inside the active worktree
2) or provide an approved DB access path
```

## Hard Stop Rule (Mandatory)

If a DB inspection task reaches any of these conditions:
- host `psql` is missing
- the target runtime does not have `psql`
- there is no verified repo-native query runner for the active repo
- Railway project / environment / service context is unknown

STOP immediately with:

```text
BLOCKED: no_sql_client_and_no_verified_query_runtime
NEEDS: approved DB query path or provisioned client/runtime
NEXT_COMMANDS:
1) verify an existing repo-native query runner inside the active worktree
2) or provide an approved DB access path
```

Do not:
- guess Railway service names
- use interactive `railway service` flows
- use ambient Railway link state from another repo/project
- install packages ad hoc in a verification pass

## Preferred Repo-Native Query Path

### Prime Radiant AI
```bash
# List public tables on the transactional DB
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc 'cd backend && poetry run python scripts/db_inspect.py tables'

# Describe a table
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc 'cd backend && poetry run python scripts/db_inspect.py describe eodhd_refresh_runs'

# Inspect refresh runs for a market date
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc "cd backend && poetry run python scripts/db_inspect.py refresh-runs --trade-date 2026-03-09"

# Read-only ad hoc SQL on the vector DB
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc "cd backend && poetry run python scripts/db_inspect.py --db vector query --sql 'SELECT 1'"
```

The wrapper is the canonical host/worktree DB path for this repo. It combines backend service env with Postgres TCP proxy coordinates so host-side inspection and migrations do not depend on `postgres.railway.internal` resolving locally.

The inspector is read-only by design and should remain the primary manual inspection path for Prime Radiant application data. It can bootstrap missing backend DB dependencies with `poetry install --only main --no-root` on the first real query.

For Prime Radiant dev EODHD operations, start from the Railway-hosted Windmill assets `f/eodhd/eodhd_trigger_and_process`, `f/eodhd/eod_realtime`, and `f/eodhd/eod_nightly`. The legacy `eodhd-cron` service is retired in dev and must not be used as a debugging or recovery target.

### Prime Radiant Windmill Incident Ladder

If the user is debugging EODHD scheduling, alerting, or enqueue failures in `dev`, use this order:

1. Confirm the canonical Windmill cluster is the unsuffixed Railway stack (`server`, `worker`, `platform`, `proxy`, `worker_native`).
2. Verify workspace `eodhd` contains:
   - `f/eodhd/eodhd_trigger_and_process`
   - `f/eodhd/eod_realtime`
   - `f/eodhd/eod_nightly`
3. Verify exactly one realtime schedule and exactly one nightly schedule exist.
4. Check Windmill run history before touching backend or database state.
5. Use the repo-native DB inspector only after the Windmill surface has been verified.

Do not:
- debug or recreate `eodhd-cron`
- treat duplicate `server-*` domains as evidence of a second valid orchestrator
- use `wmill sync push` for partial recovery
- infer Slack delivery failure from schedule failure without checking flow logs

## Direct SQL Path

Use the wrapper for direct SQL so Railway private-network DB hosts are rewritten to the service TCP proxy automatically. Direct SQL still requires host `psql`.

### Prime Radiant AI
```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --project-id <project-id> \
    --env dev \
    psql

~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --project-id <project-id> \
    --env dev \
    query --sql 'SELECT 1'
```

### Affordabot

Use the repo-native read-only inspector via the Railway Postgres wrapper:

```bash
# List public tables
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc 'cd backend && poetry run python scripts/db_inspect.py tables'

# Describe a table
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc 'cd backend && poetry run python scripts/db_inspect.py describe legislation'

# Jurisdiction/source/scrape health summary
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc 'cd backend && poetry run python scripts/db_inspect.py jurisdiction-summary --limit 25'

# Recent pipeline runs
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc 'cd backend && poetry run python scripts/db_inspect.py pipeline-runs --limit 25'

# Recent raw scrapes
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc 'cd backend && poetry run python scripts/db_inspect.py raw-scrapes --hours 24 --limit 25'

# Read-only ad hoc SQL
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    backend-python -- \
    bash -lc "cd backend && poetry run python scripts/db_inspect.py query --sql 'SELECT COUNT(*) AS c FROM jurisdictions'"
```

The inspector is read-only by contract (`SELECT`/`WITH`/`SHOW` only with mutating tokens blocked).
Do not use host `psql` as the primary Affordabot inspection path.

Canonical Railway rule:
- do not rely on ambient `railway status`
- do not guess service names
- use explicit non-interactive flags when Railway execution is required:
  `railway run -p <project-id> -e <environment> -s <service> -- <command>`

Interpretation rule:
- `No such file or directory (os error 2)` from
  `railway run ... -- psql "$DATABASE_URL"` means the runtime likely does not contain the `psql` binary.
- This is a runtime/client availability failure, not evidence that the service name is wrong.

If no verified query runtime exists, return the BLOCKED contract above.

### Common Psql Commands
```bash
# List all tables
\dt

# Describe table structure
\d+ table_name

# List databases
\l

# Quit
\q

# Run single query
psql -c "SELECT COUNT(*) FROM users;"

# Run SQL file
psql -f migration.sql
```

## Apply Migrations

### Prime Radiant AI (Alembic)
```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-postgres.sh \
    --repo-root "$PWD" \
    alembic-upgrade head
```

### Affordabot (Raw SQL)
Only use raw SQL migrations when a verified SQL client/runtime already exists for the task.
Do not guess service names or improvise a SQL runtime from an audit/verification pass.

## Common Validation Queries

### Table row counts
```sql
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;
```

### Table sizes
```sql
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Recent activity
```sql
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;
```

### Check for long-running transactions
```sql
SELECT pid, now() - pg_stat_activity.query_start AS duration, query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';
```

## Integration Points

### With Railway CLI
- Use `railway run -p <project-id> -e <env> -s <service> -- <command>` for non-interactive execution
- Prefer `~/agent-skills/scripts/dx-load-railway-auth.sh -- <command>` when Railway auth is needed
- Prefer `~/agent-skills/scripts/dx-railway-postgres.sh` for host-side DB inspection, SQL, and Alembic
- Prefer `~/agent-skills/scripts/dx-railway-run.sh -- <command>` for non-DB commands in worktrees with seeded Railway context

### With Repo-Specific Skills
- Use repo-local/backend skills for app-specific query paths when they already exist
- Use `context-database-schema` for schema-grounded codebase references

## Best Practices

### Do

✅ Use the repo-native inspector first when it exists
✅ Use `railway run --service <name>` for service isolation
✅ Use `~/agent-skills/scripts/dx-load-railway-auth.sh -- <command>` instead of `source ...`
✅ Quote `"$DATABASE_URL"` to handle special characters
✅ Use `\dt` to list tables before querying
✅ Run EXPLAIN ANALYZE for slow queries
✅ Check connection limits: `SELECT count(*) FROM pg_stat_activity;`
✅ Stop immediately if no host `psql` and no verified repo-native query runner exists
✅ Treat missing `psql` in the target runtime as a blocker unless a verified alternate query path exists
✅ Treat Railway project mismatch as a blocker until explicit context is restored

### Don't

❌ Don't put passwords in commands (use Railway env vars)
❌ Don't run migrations without backup
❌ Don't use SELECT * in production queries
❌ Don't forget to quote environment variables
❌ Don't install packages with `sudo`, `apt`, `brew`, or Docker for ad hoc DB inspection
❌ Don't write scratch query scripts outside the active worktree
❌ Don't substitute logs or HTTP endpoints for direct DB state unless you explicitly call them secondary evidence
❌ Don't infer a wrong Railway service from `psql: No such file or directory`
❌ Don't use `railway service` or similar interactive discovery commands in non-TTY sessions
❌ Don't keep probing after the blocker condition has been met
❌ Don't use ad hoc dependency installs inside a QA or audit batch to compensate for a missing query path

## What This Skill Does

✅ Enforce a safe preflight for Railway DB access
✅ Prefer repo-native inspection when available
✅ Show direct SQL path when host `psql` exists
✅ Provide migration commands and common validation queries

## What This Skill DOESN'T Do

❌ Table-specific schema details
❌ Migration troubleshooting (use migration-specific skills)
❌ DDL operations (CREATE TABLE, etc.) - use migrations
❌ Backup/restore (use railway/database skill)
❌ Full migration/DDL workflows
**Cause:** Wrong database or insufficient privileges

**Fix:**
```bash
# Use correct DATABASE_URL
echo $DATABASE_URL | psql -v ON_ERROR_STOP=1
```

## Related Skills

- **railway/database**: Create/manage Railway databases
- **context-prime-radiant-db**: Prime Radiant schema details
- **context-affordabot-db**: Affordabot schema details

---

**Last Updated:** 2025-02-08
**Skill Type:** Reference
**Average Duration:** <30s to connect
