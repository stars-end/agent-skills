you're a full-stack dev agent at a tiny fintech startup:

## DX Global Constraints (Always-On)
1) NO WRITES in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`
2) Worktree first: `dx-worktree create <beads-id> <repo>`
3) Before "done": run `~/agent-skills/scripts/dx-verify-clean.sh` (must PASS)
4) Open draft PR after first real commit
5) Final response MUST include `PR_URL` and `PR_HEAD_SHA`

## Assignment Metadata (Required)
- BEADS_EPIC: `bd-kuhj`
- BEADS_SUBTASK: `bd-kuhj`
- BEADS_DEPENDENCIES: `none`
- FEATURE_KEY: `bd-kuhj`

## Cross-VM Source of Truth (Required)
- PR_URL: to be filled from the seed PR for this spec/prompt package
- PR_HEAD_SHA: to be filled from the seed PR for this spec/prompt package
- Repo paths to read first:
  - `docs/specs/DX_V8_6_WORKSPACE_FIRST_CANONICAL_ISOLATION_SPEC.md`
  - `docs/prompts/bd-kuhj-workspace-first-implementation-prompt.md`
  - `extended/worktree-workflow/SKILL.md`
  - `extended/dx-runner/SKILL.md`
  - `extended/dx-batch/SKILL.md`
  - `extended/opencode-dispatch/SKILL.md`
  - `dispatch/multi-agent-dispatch/SKILL.md`
  - `docs/IDE_SPECS.md`

If `PR_URL` and `PR_HEAD_SHA` are missing, stop and return:
- `BLOCKED: MISSING_PR_CONTEXT`
- `NEEDS: seed PR URL and head SHA for bd-kuhj spec branch`

## Objective
Implement DX V8.6 workspace-first canonical isolation so governed dispatch, manual IDE sessions, and cleanup automation all enforce the same rule: canonical repos are clean mirrors and writable work lives in task worktrees.

## Scope
- In scope:
  - `dx-worktree` primitives for `open`, `resume`, and `evacuate-canonical`
  - `dx-runner` and `dx-batch` enforcement of externally managed non-canonical workspaces
  - manual-session UX for `opencode`, `antigravity`, `codex`, `claude`, and `gemini`
  - canonical cleanup automation and worktree-protection policy
  - skills, runbooks, and compiled baseline alignment
  - validation across canonical VMs and agent IDE entrypoints
- Out of scope:
  - filesystem read-only permissions for canonical repos
  - global `git` wrappers
  - shell hooks that block `cd`
  - Symphony orchestration changes
  - alternate recovery models not described in the spec

## Locked Decisions (Do Not Revisit)
1) No normal-policy exception for intentional canonical commits.
2) Secret-bearing files must not be pushed into remote recovery branches by default.
3) `dx-worktree open` must support both:
   - `dx-worktree open <beads-id> <repo>`
   - `dx-worktree open <beads-id> <repo> -- <command...>`
4) Recovery branch naming is:
   - `recovery/canonical-<repo>-<timestamp>`
5) Legitimate worktrees must be protected:
   - never destructively clean a worktree with an attached tmux session
   - avoid non-essential destructive worktree cleanup during working hours
6) Canonical cleanup remains separate from worktree cleanup:
   - canonicals self-heal when safe
   - skip on merge, rebase, active lock, or session-lock states

## Required Execution Order
1) `bd-kuhj.1` - add `dx-worktree` workspace/recovery primitives
2) `bd-kuhj.3` - make `dx-runner` and `dx-batch` reject canonical mutating targets
3) `bd-kuhj.4` - standardize manual IDE launch/resume UX around `dx-worktree`
4) `bd-kuhj.5` and `bd-kuhj.8` - harden cleanup automation and worktree protection
5) `bd-kuhj.6` - align skills/docs/baseline after runtime behavior is settled
6) `bd-kuhj.7` - validate and document rollout evidence

## Acceptance Criteria
1) `dx-runner` rejects canonical mutating targets with deterministic reason code `canonical_worktree_forbidden` and one exact remediation command.
2) `dx-batch` surfaces the same workspace contract and does not infer canonical workspaces.
3) `dx-worktree open` and `resume` support both path-only and `-- <command>` modes.
4) Canonical recovery writes named worktree-backed recovery outputs with machine-readable fields: `repo`, `workspace_path`, `branch`, `reason`, `timestamp`.
5) Cleanup skips merge/rebase/index-lock/session-lock states and does not disrupt tmux-attached worktrees.
6) Worktree cleanup suppresses non-essential destructive cleanup during working hours.
7) Skills/runbooks/baseline no longer imply that canonical repo roots are valid mutating targets.
8) Normal operations still work: `git fetch`, `git checkout master`, `git pull --ff-only`, `railway status`, `railway run`, `railway shell`, normal shell startup, and loading skills from canonical `~/agent-skills`.

## Execution Plan (Mandatory)
Before coding, reply with:
1) Worktree path + branch name
2) Files to modify
3) Validation commands

## Required Deliverables
- Code changes committed and pushed
- Draft/updated PR
- Validation summary
- Final response block:
  - `PR_URL: https://github.com/stars-end/agent-skills/pull/<n>`
  - `PR_HEAD_SHA: <40-char sha>`
  - `BEADS_SUBTASK: bd-kuhj.<x>` or `bd-kuhj` if completing the full epic wave

## Blockers Protocol
If blocked, return exactly:
- `BLOCKED: <reason_code>`
- `NEEDS: <single dependency/info needed>`
- `NEXT_COMMANDS:`
  1) `<command>`
  2) `<command>`

## Done Gate (Mandatory)
Do not claim complete until:
- changes are committed and pushed
- draft PR exists or existing PR updated
- `~/agent-skills/scripts/dx-verify-clean.sh` passes
- final response includes `PR_URL` and `PR_HEAD_SHA`
