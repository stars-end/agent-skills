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
2. For Prime Radiant AI, prefer the repo-native inspector first:
```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-run.sh -- \
  bash -lc 'cd backend && poetry run python scripts/db_inspect.py tables'
```
3. Check whether host `psql` exists:
```bash
command -v psql
```
4. Prefer `railway run -p/-e/-s -- ...` or `dx-railway-run.sh -- ...` over partial `railway link`.

If `psql` is missing and there is no verified repo-native query path already present, stop exactly with:

```text
BLOCKED: no_sql_client_and_no_verified_query_runtime
NEEDS: approved DB query path or provisioned client/runtime
NEXT_COMMANDS:
1) verify an existing repo-native query runner inside the active worktree
2) or provide an approved DB access path
```

## Preferred Repo-Native Query Path

### Prime Radiant AI
```bash
# List public tables on the transactional DB
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-run.sh -- \
  bash -lc 'cd backend && poetry run python scripts/db_inspect.py tables'

# Describe a table
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-run.sh -- \
  bash -lc 'cd backend && poetry run python scripts/db_inspect.py describe eodhd_refresh_runs'

# Inspect refresh runs for a market date
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-run.sh -- \
  bash -lc "cd backend && poetry run python scripts/db_inspect.py refresh-runs --trade-date 2026-03-09"

# Read-only ad hoc SQL on the vector DB
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-run.sh -- \
  bash -lc "cd backend && poetry run python scripts/db_inspect.py --db vector query --sql 'SELECT 1'"
```

The inspector is read-only by design and should be the primary manual inspection path for this repo. It can bootstrap missing backend DB dependencies with `poetry install --only main --no-root` on the first real query.

For Prime Radiant dev EODHD operations, start from the Railway-hosted Windmill assets `f/eodhd/eodhd_trigger_and_process`, `f/eodhd/eod_realtime`, and `f/eodhd/eod_nightly`. The legacy `eodhd-cron` service is rollback-only in dev and should not be the first debugging target.

## Direct SQL Path

`railway run` injects Railway environment variables into the command you execute locally. It does **not** guarantee a `psql` binary for you. Direct SQL works only when host `psql` exists.

### Prime Radiant AI
```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  railway run -p <project-id> -e dev -s backend -- \
  psql "$DATABASE_URL"
```

### Affordabot
```bash
railway run --service affordabot-pgvector -- psql "$DATABASE_URL"
```

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
cd backend && poetry run alembic upgrade head
```

### Affordabot (Raw SQL)
```bash
cp backend/migrations/006_new.sql /tmp/migrate.sql
railway run --service affordabot-pgvector -- psql "$DATABASE_URL" -f /tmp/migrate.sql
```

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
- Prefer `~/agent-skills/scripts/dx-railway-run.sh -- <command>` in worktrees with seeded Railway context

### With Repo-Specific Skills
- Use repo-local/backend skills for app-specific query paths when they already exist
- Use `context-database-schema` for schema-grounded codebase references

## Best Practices

### Do

✅ Use the repo-native inspector first when it exists
✅ Use `railway run --service <name>` for service isolation
✅ Quote `"$DATABASE_URL"` to handle special characters
✅ Use `\dt` to list tables before querying
✅ Run EXPLAIN ANALYZE for slow queries
✅ Check connection limits: `SELECT count(*) FROM pg_stat_activity;`
✅ Stop immediately if no host `psql` and no verified repo-native query runner exists

### Don't

❌ Don't put passwords in commands (use Railway env vars)
❌ Don't run migrations without backup
❌ Don't use SELECT * in production queries
❌ Don't forget to quote environment variables
❌ Don't install packages with `sudo`, `apt`, `brew`, or Docker for ad hoc DB inspection
❌ Don't write scratch query scripts outside the active worktree
❌ Don't substitute logs or HTTP endpoints for direct DB state unless you explicitly call them secondary evidence

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
