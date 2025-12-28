# Schema Sentinel (GLM-4.7)

Tightening the Inner Loop by resolving the 'Guessing Game' between code and database.

### Problem
Agents spend 3-5 commits guessing column names or type casts (UUID vs Text).

### Logic
1. Catch DB errors in `ci-lite`.
2. Map error to source code and DB schema.
3. GLM-4.7 generates the correct SQL/SQLAlchemy patch.
4. User/Agent approves the fix in 10s instead of 10m.

