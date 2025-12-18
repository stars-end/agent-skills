# Agent Bootstrap Protocol

**Tags:** #bootstrap #setup #env #dx

## 1. Run Hydration
```bash
~/agent-skills/scripts/dx-hydrate.sh
```

## 2. Verify Health
```bash
~/agent-skills/scripts/dx-status.sh
```

## 3. Usage Rules
*   **Refactoring:** Use `serena`.
*   **Planning:** Query `cass`.
*   **Committing:** Respect `pre-commit` hooks.
*   **Tooling:** **USE THE CLI.** Don't ask the user to check `gh` or `railway` status. Read `~/agent-skills/memory/playbooks/02_CLI_MASTERY.md`.

## 4. Troubleshooting
If you encounter **Dirty Repos** or **Missing Tools**, read:
`~/agent-skills/memory/playbooks/99_TROUBLESHOOTING.md`
