---
name: feature-lifecycle
description: |
  A suite of skills to manage the full development lifecycle from start to finish.
  - `start-feature`: Initializes a new feature branch and story. Spec is read from Beads (stars-end/bd).
  - `sync-feature`: Saves work with CI checks.
  - `finish-feature`: Verifies and creates a pull request.
tags: [workflow, git, feature, beads, dx]
---

# Feature Lifecycle Skills

This file defines the three core skills for agent-driven development.

## Beads-Only Product Specs Policy

Per the Beads-only product specs (stars-end/bd):
- **All Beads issues live in `stars-end/bd`** - this is the single source of truth.
- **Product repos do not contain `docs/bd-*.md` stubs** - spec is accessed via `bd show <id>`.
- **Commits must include `Feature-Key: bd-xxxx`** for traceability.

---

### `start-feature <issue-id>`

**Purpose:** Initializes a new feature branch with a test story skeleton. Reads the authoritative spec from Beads (stars-end/bd).

**Usage:**
```bash
# From any product repo (affordabot, prime-radiant-ai)
feature-lifecycle/start.sh bd-123
```

**BDD Spec:**
- **Given** I am in a product repo
- **And** I provide a Beads issue ID `bd-123`
- **When** I run `start-feature bd-123`
- **Then** a new branch `feature-bd-123` is created
- **And** a story file `docs/testing/stories/story-bd-123.yml` is created
- **And** the spec is displayed from `bd show bd-123` (stars-end/bd)
- **And** NO `docs/bd-123.md` stub file is created (spec lives in Beads)

**Important:**
- Use `bd show <issue-id>` to read the authoritative spec from `stars-end/bd`.
- Do not create `docs/bd-*.md` files - they cause spec drift.
- All commits should include `Feature-Key: bd-xxxx` in the commit message.

---

### `sync-feature [options] <message>`

**Purpose:** The "Save Button" for agents. Ensures all commits are clean by running `ci-lite` before saving. Prevents pushing broken code.

**Usage:**
```bash
# From a feature branch, commit valid work
feature-lifecycle/sync.sh "feat: add new login button

Feature-Key: bd-123"

# Force save broken work (e.g., to switch branches)
feature-lifecycle/sync.sh --wip "refactor: halfway through API change

Feature-Key: bd-123"
```

**BDD Spec:**
- **Given** I have syntax errors in my code
- **When** I run `sync-feature 'my commit'`
- **Then** the commit is **BLOCKED** and I receive an error to fix.
- **But when** I run `sync-feature --wip 'my commit'`
- **Then** the commit is created with a `[WIP]` prefix.

**Important:**
- Always include `Feature-Key: bd-xxxx` in commit messages for traceability.

---

### `finish-feature`

**Purpose:** The "Handoff" to the QA/Merge phase. Runs the full PR verification suite before a PR is created, preventing review spam with broken code.

**Usage:**
```bash
# When a feature is complete and ready for review
feature-lifecycle/finish.sh
```

**BDD Spec:**
- **Given** I am on a feature branch
- **And** the `make verify-pr` target fails
- **When** I run `finish-feature`
- **Then** the PR creation is **BLOCKED** and I am instructed to check the verification artifacts.

**Important:**
- The PR description should reference the Beads issue (`bd show bd-xxxx`).
- At least one commit must have `Feature-Key: bd-xxxx` in the commit trailers.
