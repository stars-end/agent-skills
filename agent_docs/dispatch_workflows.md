# Dispatch Workflows

## Primary: dx-runner (Canonical)

```bash
# Start governed job
dx-runner start --provider opencode --beads bd-xxx --prompt-file /tmp/p.prompt

# Check status
dx-runner status --json
dx-runner check --beads bd-xxx --json

# Get report
dx-runner report --format json
```

## Batch Orchestration: dx-batch

```bash
# Run multiple items in waves
dx-batch start --items bd-aaa,bd-bbb,bd-ccc --max-parallel 2

# Diagnose issues
dx-batch doctor --wave-id <wave-id> --json
```

## Fallback: cc-glm

```bash
# Reliability backstop
dx-runner start --provider cc-glm --beads bd-xxx --prompt-file /tmp/p.prompt
```

## See Also
- `extended/dx-runner/SKILL.md` - Full dx-runner documentation
- `extended/cc-glm/SKILL.md` - cc-glm fallback patterns
- `docs/DX_FLEET_SPEC_V7.7.md` - Fleet coordination spec
