## External Beads Database (CRITICAL)

### Requirement

ALL agents MUST use centralized external beads database:

```bash
export BEADS_DIR="$HOME/bd/.beads"
```

### Verification

Every session:

```bash
echo $BEADS_DIR
# Expected: /home/fengning/bd/.beads

# If not set:
cd ~/agent-skills
./scripts/migrate-to-external-beads.sh
source ~/.zshrc
```

### Architecture

```
~/bd/.beads/              (Central database)
├── beads.db              (SQLite)
├── issues.jsonl          (Export)
├── config.yaml           (Config)
└── .git/                 (Multi-VM sync)
```

### Why External DB

| Problem | Solution |
|---------|----------|
| `.beads/` causes git conflicts | External DB separate from code |
| Each repo isolated | Single shared database |
| Multi-VM sync complex | One `~/bd` repo via git |
| Agent context fragments | All agents see same issues |
