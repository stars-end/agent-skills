# Beads Planning Patterns

## Default Epic Pattern

Use this for most multi-phase work:

1. `epic`
2. `feature` for the first executable outcome
3. `feature` for the second outcome
4. `task` or `chore` for cleanup / rollout / verification

## Dependency Rules

- `parent-child`: hierarchy only
- `blocks`: real sequencing dependency
- `discovered-from`: follow-on work found during execution
- `related`: contextual link only

## Good Child Task Titles

- `Implement Dolt-only fail-fast Beads startup contract`
- `Migrate IDE runtime env to canonical Beads pins`
- `Add rollout verification runbook for canonical VMs`

Avoid:
- `Fix files`
- `Misc cleanup`
- `Investigate stuff`

## Choosing Issue Types

- `epic`: multi-phase outcome with several child items
- `feature`: coherent implementation outcome
- `task`: focused engineering action
- `chore`: narrow maintenance / cleanup
- `decision`: explicit architecture or policy choice

## Validation Thinking

Every child task should imply a proof:
- command output
- test target
- health check
- review artifact
- deployment verification

If you cannot name the proof, the task is underspecified.
