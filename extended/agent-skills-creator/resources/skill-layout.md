# Skill Layout

## Minimal Canonical Skill

```text
<category>/<skill-name>/
├── SKILL.md
└── agents/
    └── openai.yaml   # optional but recommended when UI discovery matters
```

## Add `resources/` Only When Needed

Add `resources/` when:
- the main skill would otherwise become noisy
- examples or templates are useful
- the workflow has one or two reusable supporting documents

Avoid resource sprawl.

## Main File Priorities

Every canonical skill should answer:
1. what is it for
2. when should it trigger
3. what is the active workflow
4. what is the current contract

Everything else is secondary.
