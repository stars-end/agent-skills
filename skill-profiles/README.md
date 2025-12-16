# Skill Profiles

Repo-specific manifests used by `skills-doctor` to validate `~/.agent/skills` contains the right shared skills for that repo.

Format (`*.json`):

```json
{
  "repo": "prime-radiant-ai",
  "required": ["issue-first", "sync-feature-branch", "create-pull-request"],
  "recommended": ["lockfile-doctor", "railway-doctor"]
}
```

Notes:
- These profiles should only reference skills that live in `agent-skills` (i.e., directories in `~/.agent/skills`).
- Repo-local “context skills” (under a repo’s `.claude/skills/`) are intentionally out of scope here.

