---
name: database-quickref
description: Quick reference for Railway Postgres operations. Use when user asks to check database, run queries, verify data, inspect tables, or mentions psql, postgres, database, "check the db", "validate data".
tags: [database, postgres, railway, psql]
allowed-tools:
  - Bash(railway:*)
  - Bash(psql)
  - Read
---

# Database Quick Reference

Railway Postgres quick reference for database operations (<30s to connect).

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

## Connect to Railway Postgres

### Prime Radiant AI
```bash
railway run --service pgvector -- psql "$DATABASE_URL"
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
- Uses `railway run` for service isolation
- Service names are repo-specific (pgvector, affordabot-pgvector)
- `DATABASE_URL` injected automatically

### With Repo-Specific Skills
- **prime-radiant**: Use `context-prime-radiant-db` for schema details
- **affordabot**: Use `context-affordabot-db` for schema details

## Best Practices

### Do

✅ Use `railway run --service <name>` for service isolation
✅ Quote `"$DATABASE_URL"` to handle special characters
✅ Use `\dt` to list tables before querying
✅ Run EXPLAIN ANALYZE for slow queries
✅ Check connection limits: `SELECT count(*) FROM pg_stat_activity;`

### Don't

❌ Don't put passwords in commands (use Railway env vars)
❌ Don't run migrations without backup
❌ Don't use SELECT * in production queries
❌ Don't forget to quote environment variables

## What This Skill Does

✅ Show Railway Postgres connection commands
✅ List common psql commands
✅ Provide migration commands
✅ Common validation queries

## What This Skill DOESN'T Do

❌ Table-specific schema details (use context-*-db skills)
❌ Migration troubleshooting (use migration-specific skills)
❌ DDL operations (CREATE TABLE, etc.) - use migrations
❌ Backup/restore (use railway/database skill)

## Examples

### Example 1: Quick table check
```
User: "Check how many users we have"

AI execution:
1. Connects: railway run --service pgvector -- psql "$DATABASE_URL"
2. Runs: SELECT COUNT(*) FROM users;

Outcome: ✅ Returns count
```

### Example 2: Schema inspection
```
User: "What columns does the holdings table have?"

AI execution:
1. Connects: railway run --service pgvector -- psql "$DATABASE_URL"
2. Runs: \d+ holdings

Outcome: ✅ Returns table structure
```

### Example 3: Run custom query
```
User: "Find holdings without cost basis"

AI execution:
1. Constructs: SELECT * FROM holdings WHERE cost_basis IS NULL;
2. Connects and runs query

Outcome: ✅ Returns problem rows
```

## Troubleshooting

### "service not found"
**Cause:** Service name incorrect or service doesn't exist

**Fix:**
```bash
# List all services
railway status

# Check for Postgres services
railway status --json | grep -i postgres
```

### "connection refused"
**Cause:** Database not ready or wrong credentials

**Fix:**
```bash
# Check service status
railway status

# Verify DATABASE_URL is set
railway variables | grep DATABASE_URL
```

### "permission denied"
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
