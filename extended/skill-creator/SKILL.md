---
name: skill-creator
description: |
  Deprecated compatibility shim for legacy skill creation requests.
  Use when the user still says "skill-creator" or asks to create a skill, then route canonical `~/agent-skills` work to `agent-skills-creator`.
  Route implementation-plan/spec requests with Beads epic+dependencies+subtasks to `implementation-planner`.
tags: [meta, skill-creation, compatibility, deprecation]
allowed-tools:
  - Read
---

# Skill Creator (Deprecated)

This skill remains only to preserve old trigger phrases.

## Canonical Routing

- For creating or updating shared skills in `~/agent-skills`, use `agent-skills-creator`.
- For "write a comprehensive implementation plan with Beads epic, dependencies, and subtasks", use `implementation-planner`.

## Why This Skill Was Deprecated

This legacy skill taught assumptions that are no longer the active repo contract:
- `.claude/skills/...` as the primary layout
- legacy V3 wording as the source of truth
- outdated helper flows that are not part of the current repo
- historical guidance that predates the current baseline regeneration contract

## What To Do Instead

### Canonical Skill Authoring

Use `agent-skills-creator` when the task is:
- add a skill
- refactor a skill
- deprecate a skill
- regenerate baseline after skill changes

### Canonical Planning

Use `implementation-planner` when the task is:
- implementation plan
- migration spec
- epic + subtasks + dependencies
- rollout plan

## Compatibility Rule

If this skill triggers because the user said "skill-creator":
1. keep the user intent
2. route the actual work to `agent-skills-creator`
3. only keep this skill name alive long enough to avoid breaking legacy activation patterns
