# BDD Specifications for Agentic DX Skills

## Skill: start-feature

**Scenario: Agent starts a new feature**
- **Given** I am in a product repo
- **And** I provide a Beads issue ID `bd-123`
- **When** I run `start-feature bd-123`
- **Then** a new branch `feature-bd-123` is created
- **And** a doc file `docs/bd-123.md` is created (if missing)
- **And** a story file `docs/testing/stories/story-bd-123.yml` is created (if missing)
- **And** I am switched to the new branch

## Skill: sync-feature

**Scenario: Agent saves valid work**
- **Given** I have uncommitted changes
- **And** `make ci-lite` passes
- **When** I run `sync-feature 'feat: add login'`
- **Then** changes are committed and pushed
- **And** the output confirms success

**Scenario: Agent tries to save broken work**
- **Given** I have syntax errors
- **When** I run `sync-feature 'feat: broken'`
- **Then** the command fails with exit code 1
- **And** the output says "❌ COMMIT BLOCKED: CI-LITE FAILED"
- **And** no commit is created

**Scenario: Agent forces broken save**
- **Given** I have syntax errors
- **When** I run `sync-feature --wip 'saving wip'`
- **Then** changes are committed with `[WIP]` prefix
- **And** changes are pushed

## Skill: finish-feature

**Scenario: Agent finishes work**
- **Given** I am on a feature branch
- **And** `make verify-pr` passes
- **When** I run `finish-feature`
- **Then** the branch is rebased on master
- **And** a PR is opened via `gh pr create`

**Scenario: Verification fails**
- **Given** smoke tests fail
- **When** I run `finish-feature`
- **Then** the command fails
- **And** no PR is created
- **And** the output says "PR Blocked. Verification failed."

