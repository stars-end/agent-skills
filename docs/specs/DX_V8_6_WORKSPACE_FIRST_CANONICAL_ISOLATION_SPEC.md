# DX V8.6 Workspace-First Canonical Isolation

## Purpose

Move DX V8.6 from runner-managed workspace inference to a workspace-first contract that works for:

- governed dispatch via `dx-runner` and `dx-batch`
- manual `opencode`, `antigravity`, `codex`, `claude`, and `gemini` sessions
- canonical cleanup automation on every canonical VM
- future Symphony orchestration on top of stable substrate commands

The target mental model is binary:

- canonical repos under `~/` are clean mirrors
- writable work happens in `/tmp/agents/<beads-id>/<repo>`

## Problem Statement

Today, the substrate boundary is fuzzy:

- `dx-runner` can still accept canonical repo paths as execution targets
- worktree resolution can fall back to repo cwd or prompt-file ancestry
- manual IDE sessions on canonical VMs do not share one consistent recovery path
- canonical cleanup behavior is not expressed as a named workspace recovery contract
- docs and skills still describe a mix of worktree-first and runner-inferred behavior

This creates hidden state, host drift, and founder intervention when canonicals become dirty or off-trunk.

## Design Goals

1. One workspace contract for all mutating agent paths.
2. No stash-first recovery model.
3. Canonical repos remain readable and syncable, but are not task work surfaces.
4. Recovery is explicit, discoverable, and machine-parseable.
5. Future Symphony can orchestrate substrate commands without re-implementing workspace logic.

## Non-Goals

- Do not make canonical repos filesystem read-only.
- Do not wrap or replace normal `git`, `railway`, or `zsh` behavior globally.
- Do not move Beads orchestration into `dx-worktree`.
- Do not make Symphony responsible for canonical recovery logic.
- Do not support “intentional canonical commit” as a normal DX workflow.

## Architecture Boundary

### `dx-worktree`

Owns workspace lifecycle and recovery:

- `create`
- `open`
- `resume`
- `evacuate-canonical`
- `cleanup` and `prune`

`dx-worktree` is the single shared primitive for manual and governed workflows.

`dx-worktree open` should support both:

```bash
dx-worktree open <beads-id> <repo>
dx-worktree open <beads-id> <repo> -- <command...>
```

Behavior:

- without `-- <command...>`: print the workspace path and status metadata
- with `-- <command...>`: `exec` the requested IDE or command inside the prepared workspace

### `dx-runner` and `dx-batch`

Own governed execution inside a valid, externally managed workspace:

- require non-canonical workspace for mutating runs
- reject canonical execution targets deterministically
- report workspace path and failure reason in stable output

### Manual IDE Sessions

Manual sessions on canonical VMs use the same entrypoint pattern:

```bash
dx-worktree open <beads-id> <repo> -- <ide-or-command>
dx-worktree resume <beads-id> <repo> -- <ide-or-command>
```

Examples:

```bash
dx-worktree open bd-kuhj.4 agent-skills -- opencode
dx-worktree open bd-kuhj.4 prime-radiant-ai -- antigravity
dx-worktree open bd-kuhj.4 affordabot -- codex
dx-worktree open bd-kuhj.4 llm-common -- claude
```

### Cleanup Automation

Cleanup scripts remain the universal backstop for any source of canonical dirt:

- governed runner mistake
- manual IDE misuse
- ad hoc shell editing

They should recover work into explicit workspace paths and restore canonical mirrors when safe.

## Required Runtime Contract

### Allowed Mutating Paths

Mutating agent execution is valid only when the effective workspace is outside canonical repo roots and under an approved writable prefix such as:

- `/tmp/agents`
- `/tmp/dx-runner`
- other explicit temporary prefixes added by DX configuration

### Forbidden Paths

Mutating execution must fail for:

- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`
- prompt-file ancestry resolving to those roots
- inherited cwd resolving to those roots

### Deterministic Failure

Forbidden canonical target attempts must emit:

- `reason_code=canonical_worktree_forbidden`
- exact rejected path
- exact remediation command

Recommended remediation format:

```text
Run: dx-worktree create <beads-id> <repo>
```

## Recovery Contract

### Primary Recovery Plane

Canonical recovery uses explicit worktree-backed branches, not stash.

Every successful recovery should produce:

- `repo`
- `workspace_path`
- `branch`
- `reason`
- `timestamp`

Standard recovery branch naming:

- `recovery/canonical-<repo>-<timestamp>`

### Skip Conditions

Automation must skip destructive recovery and alert instead when any of the following are present:

- `.git/index.lock`
- merge in progress
- rebase in progress
- active session lock

There is no normal-policy exception for intentional canonical commits. Canonical repos are mirrors, not supported durable work locations.

### Secret Handling

Obvious secret-bearing files should not be pushed into remote recovery branches by default. If encountered during canonical recovery, they should be quarantined locally with an explicit alert and referenced in structured recovery output.

## Worktree Protection Policy

Legitimate task work under `/tmp/agents/...` is protected more conservatively than canonical mirrors.

### Worktree Rules

- never prune or evacuate a worktree with an attached tmux session
- suppress non-essential destructive worktree cleanup during working-hours windows by default
- allow explicit override only through documented maintenance paths, not implicit cron behavior

### Canonical Rules

- canonical repos still self-heal when safe
- canonical cleanup must skip active lock, merge, rebase, and session-lock states
- canonical cleanup must not disturb active protected worktrees

This split is intentional:

- worktrees are active durable task state
- canonical repos are disposable mirrors

## Compatibility Constraints

The implementation must preserve:

- `git fetch`
- `git checkout master`
- `git pull --ff-only`
- `railway status`
- `railway run`
- `railway shell`
- normal `zsh` startup
- skills and baseline rails loading from canonical `~/agent-skills`

The only behavior intentionally blocked is mutating agent execution against canonical repo roots.

## Symphony Compatibility

This substrate is explicitly designed so Symphony can remain thin later.

Symphony should orchestrate:

- `dx-worktree create/open/resume/evacuate-canonical`
- `dx-runner start/check/report`
- `dx-batch start/status/report`

Symphony should not own:

- workspace inference
- canonical cleanup policy
- provider-specific path exceptions

## Beads Execution Plan

### Epic

- `bd-kuhj` - DX V8.6: Workspace-first canonical isolation across governed and manual agent sessions

### Child Tasks

- `bd-kuhj.1` - `dx-worktree: add open/resume/evacuate-canonical workflow primitives`
- `bd-kuhj.2` - `Spec: define workspace-first DX V8.6 contract and recovery model`
- `bd-kuhj.3` - `dx-runner and dx-batch: enforce external non-canonical workspace contract`
- `bd-kuhj.4` - `Manual IDE sessions on canonical VMs: standardize workspace-first launch and recovery UX`
- `bd-kuhj.5` - `Canonical cleanup automation: evacuate to named worktree recovery paths and self-heal every host`
- `bd-kuhj.6` - `Skills, docs, and baseline: align all dispatch and IDE surfaces to workspace-first DX V8.6`
- `bd-kuhj.7` - `Validation and rollout: prove workspace-first contract across canonical VMs and agent IDEs`
- `bd-kuhj.8` - `Worktree protection policy: preserve active tmux work and avoid destructive cleanup during working hours`

### Dependency Graph

- `bd-kuhj.1` depends on `bd-kuhj.2`
- `bd-kuhj.3` depends on `bd-kuhj.1`
- `bd-kuhj.4` depends on `bd-kuhj.1`
- `bd-kuhj.5` depends on `bd-kuhj.2`
- `bd-kuhj.8` depends on `bd-kuhj.2`
- `bd-kuhj.6` depends on `bd-kuhj.1`, `bd-kuhj.3`, `bd-kuhj.4`, `bd-kuhj.5`, `bd-kuhj.8`
- `bd-kuhj.7` depends on `bd-kuhj.3`, `bd-kuhj.4`, `bd-kuhj.5`, `bd-kuhj.6`, `bd-kuhj.8`

## Implementation Phases

### Phase 1: Spec and Workspace Primitives

- land this spec
- implement `dx-worktree open`
- implement `dx-worktree resume`
- implement `dx-worktree evacuate-canonical`
- standardize structured output fields

### Phase 2: Governed Dispatch Enforcement

- remove canonical roots from mutating path allowlists
- reject canonical path resolution in `dx-runner`
- apply same rule to OpenCode and Gemini mutating runs
- ensure `dx-batch` surfaces the same remediation path

### Phase 3: Manual Session UX

- make manual IDE instructions center on `dx-worktree open` and `resume`
- keep session-start warnings as secondary hints where supported
- avoid stash-based guidance in default recovery text

### Phase 4: Canonical Cleanup Hardening

- recover canonical dirt into named worktree paths
- add skip-and-alert semantics for merge, rebase, and lock states
- keep local canonical normalization on all hosts
- preserve controller-only GitHub write policy where still needed

### Phase 5: Worktree Protection Hardening

- protect tmux-attached worktrees from destructive cleanup
- honor working-hours cleanup windows for legitimate worktrees
- keep worktree cleanup policy and canonical cleanup policy explicitly separate

### Phase 6: Docs, Skills, and Baseline

- align AGENTS and compiled baseline
- align dispatch skills and worktree skill
- align IDE specs and runbooks

### Phase 7: Validation and Rollout

- automated tests for canonical-path rejection and recovery semantics
- live smoke checks on canonical VMs
- explicit evidence that `git`, `railway`, `zsh`, and skills loading are unaffected

## Acceptance Criteria

- governed mutating runs cannot target canonical repos
- manual IDE workflows use `dx-worktree` as the default launch surface
- canonical recovery no longer depends on stash as the primary mechanism
- every recovery path is explicit and discoverable
- docs, skills, and baseline all describe the same contract
- the contract remains safe for normal `git`, `railway`, and shell workflows

## Risks and Mitigations

- Risk: overloading `dx-worktree` into a workflow engine
  - Mitigation: keep command surface narrow and substrate-focused

- Risk: cleanup disrupting active canonical misuse sessions
  - Mitigation: skip on active locks; treat canonical active work as unsupported and recover when safe

- Risk: docs lagging runtime behavior
  - Mitigation: make `bd-kuhj.6` blocking for final validation and closeout

- Risk: future Symphony duplicates workspace logic
  - Mitigation: keep machine-readable outputs stable and explicit now
