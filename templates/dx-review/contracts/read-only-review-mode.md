## Read-Only Review Mode

This review lane is read-only by contract.

- Allowed command classes:
  - read/list/search: `ls`, `find`, `rg`, `sed`, `cat`, `head`, `tail`
  - git inspection only: `git status`, `git diff`, `git show`, `git log`
  - non-mutating test discovery: `pytest --collect-only` (or equivalent list-only modes)
- Denied command classes:
  - filesystem writes and edits
  - package installs, environment mutation, service restarts
  - `git add`, `git commit`, `git push`, branch mutation
  - secret retrieval commands
  - destructive operations

Treat this as a hard constraint for reviewer behavior.

Enforcement is provider-specific best effort. `dx-review summarize` should report:
- `provider_enforced`: provider sandbox/permissions enforced read-only behavior
- `contract_only`: no hard sandbox, behavior constrained by explicit contract
- `unavailable`: provider could not express or apply read-only constraints
