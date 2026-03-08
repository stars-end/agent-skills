# Deprecation Pattern

Use this when an old skill name still has recognition value but should no longer be the canonical implementation path.

## Description Pattern

```yaml
description: |
  Deprecated compatibility shim for <old-skill-name>.
  Use when users still ask for the legacy skill name, then route canonical work to `<new-skill-name>`.
```

## Body Pattern

- say the old skill is deprecated
- state the new canonical skill name
- state the one-line routing rule
- remove stale historical implementation detail

## Use Cases

- replacing a generic skill with a more specific one
- migrating from local-only conventions to repo-canonical workflows
- preserving legacy trigger phrases without keeping legacy behavior
