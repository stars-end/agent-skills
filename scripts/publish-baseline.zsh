#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OUTFILE="$REPO_ROOT/AGENTS.md"
DIST_DIR="$REPO_ROOT/dist"
BASELINE_FILE="$DIST_DIR/universal-baseline.md"
CONSTRAINTS_FILE="$DIST_DIR/dx-global-constraints.md"
NAKOMI_FILE="$REPO_ROOT/@NAKOMI.md"
SOURCE_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
mkdir -p "$DIST_DIR"

render_nakomi_for_embed() {
  sed -E 's/^(#+)/#\1/' "$NAKOMI_FILE"
}

verify_nakomi_generation() {
  local target="$1"
  grep -q "## Founder Cognitive Load Policy (Binary)" "$target"
  grep -q "## Long-Term Payoff Bias" "$target"
  grep -q "No burn-in, phased cutover, transition periods, or dual-path rollouts in dev/staging." "$target"
}

# 1. Generate Global Constraints (Layer A subset)
cat > "$CONSTRAINTS_FILE" <<'EOF'
# DX Global Constraints (V8.4)
<!-- AUTO-GENERATED - DO NOT EDIT -->

## 1) Canonical Repository Rules
**Canonical repositories** (read-mostly clones):
- \`~/agent-skills\`
- \`~/prime-radiant-ai\`
- \`~/affordabot\`
- \`~/llm-common\`

### Enforcement
**Primary**: Git pre-commit hook blocks commits when not in worktree
**Safety net**: Daily sync to origin/master (non-destructive)

### Workflow
Always use worktrees for development:
\`\`\`bash
dx-worktree create bd-xxxx repo-name
cd /tmp/agents/bd-xxxx/repo-name
# Work here
\`\`\`

## 1.5) Canonical Beads Contract (V8.4)
- **Canonical Beads repo is always \`~/bd\`** (remote must be \`stars-end/bd\`).
- **Run \`dx-runner\` / \`dx-batch\` control-plane commands from \`~/bd\`**.
- **Never run mutating Beads commands from app repos** (\`~/prime-radiant-ai\`, \`~/agent-skills\`, etc.) unless explicitly using a documented override.
- **Backend must be Dolt server mode** for multi-VM/multi-agent reliability.
- **Legacy macOS \`io.agentskills.ru\` LaunchAgent is disabled by policy** (use cron/systemd schedules only).
- **Before dispatch**: verify \`bd dolt test --json\` succeeds and Beads service is active on the host.
- **\`beads.role\` self-heal**: if mutating \`bd\` commands warn \`beads.role not configured\` while \`bd dolt test --json\` passes, run \`bd config set beads.role maintainer\` before escalating. This is local config drift, not a hub outage.
- **Host service contract**:
  - Linux canonical VMs: \`systemctl --user is-active beads-dolt.service\`
  - macOS canonical host: \`launchctl print gui/\$(id -u)/com.starsend.beads-dolt\`
- **Source-of-truth runbook**: \`~/agent-skills/docs/PRIME_RADIANT_BEADS_DOLT_RUNBOOK.md\`

## 2) V8 DX Automation Rules
1. **No auto-merge**: never enable auto-merge on PRs — humans merge
2. **No PR factory**: one PR per meaningful unit of work
3. **No canonical writes**: always use worktrees
4. **Feature-Key mandatory**: every commit needs \`Feature-Key: bd-<beads-id>\`

## 3) PR Metadata Rules (Blocking In CI)
- **PR title must include a Feature-Key**: include \`bd-<beads-id>\` somewhere in the title (e.g. \`bd-f6fh: ...\`)
- **PR body must include Agent**: add a line like \`Agent: <agent-id>\`

## 4) Delegation Rule (V8.4 - Batch by Outcome)
- **Primary rule**: batch by outcome, not by file. One agent per coherent change set.
- **Default parallelism**: 2 agents, scale to 3-4 only when independent and stable.
- **Dispatch threshold**: implement directly for scoped work estimated under 60 minutes; dispatch only for >=60 minute, clearly parallelizable outcomes.
- **Do not delegate**: security-sensitive changes, architectural decisions, or high-blast-radius refactors.
- **Orchestrator owns outcomes**: review diffs, run validation, commit/push with required trailers.
- **See Section 6** for detailed parallel orchestration patterns.

## 5) Secrets + Env Sources (V8.4 - Railway Context Mandatory)
- **Railway context is MANDATORY for dev work**:
  - interactive: \`railway shell\`
  - worktree/automation-safe: \`railway run -p <project-id> -e <env> -s <service> -- <cmd>\`
- **Do not require canonical repo cwd for Railway context**; worktrees are first-class.
- **API keys**: \`op://dev/Agent-Secrets-Production/<FIELD>\` (see SECRETS_INDEX.md).
- **Railway CLI token**: \`op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN\` for CI/automation.
- **Quick reference**: use the \`op-secrets-quickref\` skill.

### 5.1) Agent Onboarding SOP (Required First Steps)

New agents MUST complete these steps before any other work:

**Step 1: Load 1Password Service Account**
\`\`\`bash
# Recommended helper
~/agent-skills/scripts/dx-load-railway-auth.sh -- op whoami

# Fallback search order if manual recovery is needed:
#   1. ~/.config/systemd/user/op-<canonical-host-key>-token
#   2. ~/.config/systemd/user/op-<canonical-host-key>-token.cred
#   3. ~/.config/systemd/user/op_token
#   4. ~/.config/systemd/user/op_token.cred

# Verify
op whoami  # Must show: User Type: SERVICE_ACCOUNT
\`\`\`

**Step 2: Authenticate Railway CLI**
\`\`\`bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami
\`\`\`

**Step 3: Verify Full Stack**
\`\`\`bash
op item list --vault dev  # Should list items
railway status            # Should show project context
\`\`\`

**Common Issues:**
- \`op whoami\` shows "account is not signed in" → Load OP_SERVICE_ACCOUNT_TOKEN
- \`railway whoami\` shows "Unauthorized" → Load OP + Railway auth in the same invocation (not separate tool calls)
- repeated auth failures across shell/tool calls → Use \`~/agent-skills/scripts/dx-load-railway-auth.sh -- <command>\`
- Token file not found → Run \`~/agent-skills/scripts/create-op-credential.sh\`

### 5.2) Railway Link Non-Interactive Usage (CRITICAL)

Agents can ONLY use `railway link` with ALL required flags:

Required flags: `--project <id-or-name>`, `--environment <name>`
Optional flags| `--service <name>`
Recommended  | `--json`

```bash
# CORRECT - Fully non-interactive
railway link --project <project-id> --environment <env> --service <service> --json

railway link --project my-app --environment staging --json

# WRONG - Will block waiting for input
railway link
railway link --project my-project  # missing --environment
```

**Why**: Railway CLI shows visual prompts but completes successfully when all flags are provided.

**Alternative**: Use `railway run` without linking
```bash
# Direct command execution with Railway context
railway run -p <project-id> -e <env> -s <service> -- <command>

# Using context from worktree
dx-railway-run.sh -- <command>
```

**Context files** (created by worktree-setup.sh)
- Location: `/tmp/agents/.dx-context/<beads-id>/<repo>/railway-context.env`
- Contains: `RAILWAY_PROJECT_ID`, `RAILWAY_ENVIRONMENT`, `RAILWAY_SERVICE`
- Used by: `dx-railway-run.sh` to provide Railway context in worktrees

### 5.3) Blocking Skill Contracts Are Binding

If a named skill contains an explicit `BLOCKED` contract:
- agents MUST return that contract verbatim once the blocker is reached
- agents MUST NOT continue speculative retries after that point
- agents MUST NOT substitute interactive CLI discovery, guessed service names, or ad hoc runtime mutation for the documented blocker response
- `No such file or directory` for a requested binary means the binary/runtime is missing unless the skill explicitly says otherwise
- when Railway execution is required, agents must use explicit non-interactive context (`-p/-e/-s`) or a verified repo-native wrapper
- ambient Railway link state from another repo/project is not sufficient evidence of correct target context

## 6) Parallel Agent Orchestration (V8.4)

### Pattern: Plan-First, Batch-Second, Commit-Only

1. **Create plan** (file for large/cross-repo, Beads notes for small)
2. **Batch by outcome** (1 agent per repo or coherent change set)
3. **Execute in waves** (parallel where dependencies allow)
4. **Commit-only** (agents commit, orchestrator pushes once per batch)

### Task Batching Rules

| Files | Approach | Plan Required |
|-------|----------|---------------|
| 1-2, same purpose | Single agent | Mini-plan in Beads |
| 3-5, coherent change | Single agent | Plan file recommended |
| 6+ OR cross-repo | Batched agents | Full plan file required |

### Dispatch Method

**Canonical: dx-runner (governed multi-provider runner)**

\`\`\`bash
# OpenCode throughput lane
dx-runner start --provider opencode --beads bd-xxx --prompt-file /tmp/p.prompt

# Shared monitoring/reporting
dx-runner status --json
dx-runner check --beads bd-xxx --json
\`\`\`

**Canonical batch orchestrator: dx-batch (orchestration-only over dx-runner)**

\`\`\`bash
# Execute implement -> review waves with deterministic ledger/contracts
dx-batch start --items bd-aaa,bd-bbb --max-parallel 2

# Diagnose stuck waves
dx-batch doctor --wave-id <wave-id> --json
\`\`\`

**Direct OpenCode lane (advanced, non-governed)**

\`\`\`bash
# Headless single-run lane
opencode run -m zhipuai-coding-plan/glm-5 "Implement task T1 from plan.md"

# Legacy server lane for parallel clients (opt-in only)
opencode serve --hostname 127.0.0.1 --port 4096
opencode run --attach http://127.0.0.1:4096 -m zhipuai-coding-plan/glm-5 "Implement task T2 from plan.md"
\`\`\`

**Reliability backstop: cc-glm via dx-runner**

\`\`\`bash
# Start governed fallback job
dx-runner start --provider cc-glm --beads bd-xxx --prompt-file /tmp/p.prompt

# Monitor fallback jobs
dx-runner status --json
dx-runner check --beads bd-xxx --json
\`\`\`

**Optional: Task tool (Codex runtime only)**

\`\`\`yaml
Task:
  description: "T1: [batch name]"
  prompt: |
    You are implementing task T1 from plan.md.
    ## Context
    - Dependencies: [T1 has none / T2, T3 complete]
    ## Your Task
    - repo: [repo-name]
    - location: [file1, file2, ...]
    ## Instructions
    1. Read all files first
    2. Implement changes
    3. Commit (don't push)
    4. Return summary
  run_in_background: true
\`\`\`

**Cross-VM: dx-dispatch** (compat wrapper to \`dx-runner\` for remote execution)

### dx-runner Best Practices

- Run \`dx-runner preflight --provider <provider>\` before starting a wave.
- Always pass a unique Beads id per run: \`--beads bd-...\`.
- Use \`--prompt-file\` with immutable prompt artifacts, not inline ad hoc prompts.
- Monitor with \`status --json\` + \`check --json\`; automate on \`reason_code\`/\`next_action\`.
- Use \`report --format json\` as the source of truth for outcome and metrics.
- Prefer one controlled restart max; then escalate using failure taxonomy.
- Run \`dx-runner prune\` periodically to clear stale PID ghosts.
- For OpenCode, enforce canonical model \`zhipuai-coding-plan/glm-5\`; fallback provider if unavailable.

### Monitoring (Simplified)

- **Check interval**: 5 minutes
- **Signals**: 1) Process alive, 2) Log advancing
- **Restart policy**: 1 restart max, then escalate
- **Check**: \`ps -p [PID]\` and \`tail -20 [log]\`

### Anti-Patterns

- One agent per file (overhead explosion)
- No plan file for cross-repo work (coordination chaos)
- Push before review (PR explosion)
- Multiple restarts (brittle)

### Fast Path for Small Work

For 1-2 file changes, use Beads notes instead of plan file:

\`\`\`markdown
## bd-xxx: Task Name
### Approach
- File: path/to/file
- Change: [what]
- Validation: [how]
### Acceptance
- [ ] File modified
- [ ] Validation passed
- [ ] PR merged
\`\`\`

References:
- \`~/agent-skills/docs/ENV_SOURCES_CONTRACT.md\`
- \`~/agent-skills/docs/SECRET_MANAGEMENT.md\`
- \`~/agent-skills/scripts/benchmarks/opencode_cc_glm/README.md\`
- \`~/agent-skills/extended/dx-runner/SKILL.md\`
- \`~/agent-skills/extended/cc-glm/SKILL.md\`

Notes:
 - PR metadata enforcement exists to keep squash merges ergonomic.
 - If unsure what to use for Agent, use platform id (see \`DX_AGENT_ID.md\`).

## 7) Frontend Evidence Contract (Required for UI/UX Claims)

When changing frontend files in \`~/prime-radiant-ai\`, agents MUST follow this workflow:

### Pre-PR Workflow
\`\`\`bash
# 1. Build and verify
pnpm --filter frontend build
pnpm --filter frontend type-check
pnpm --filter frontend lint:css

# 2. Run visual regression (start preview first)
pnpm --filter frontend preview --port 5173 &
VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual

# 3. If baselines need update, justify and commit
VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual:update
\`\`\`

### Route Matrix Verification
- **no-cookie mode**: \`/\`, \`/sign-in\`, \`/sign-up\`
- **bypass-cookie mode**: \`/v2\`, \`/brokerage\` (if auth bypass available)

### Runtime Health Requirements
- No "Unexpected Application Error" on page
- No console errors containing: \`clerk\`, \`ClerkProvider\`, \`Unhandled\`, \`TypeError\`
- Clean page render for all tested routes

### CI Workflows (Auto-triggered)
- \`.github/workflows/visual-quality.yml\` - Stylelint + Visual Regression
- \`.github/workflows/lighthouse.yml\` - Performance budgets

### Required PR Body Section
\`\`\`markdown
## Frontend Evidence

### Route Matrix
| Route | Desktop | Mobile | Status |
|-------|---------|--------|--------|
| / | ✅ | ✅ | Pass |

### Runtime Health
- Console errors: 0
- Unexpected Application Error: No

### Evidence
- Commit SHA: [hash]
- Visual tests: [X] passed
\`\`\`

**Full Template:** \`~/agent-skills/templates/frontend-evidence-contract.md\`

### Pass/Fail Criteria
- ✅ Visual tests pass (or baselines updated with justification)
- ✅ CI checks green (Stylelint, Visual Regression, Lighthouse)
- ❌ Missing evidence section blocks PR
- ❌ Evidence contradicts claims blocks PR
EOF

# Header for AGENTS.md
cat > "$OUTFILE" <<EOF
# AGENTS.md — Agent Skills Index
<!-- AUTO-GENERATED -->
<!-- Source SHA: $SOURCE_SHA -->
<!-- Last updated: $TIMESTAMP -->
<!-- Regenerate: make publish-baseline -->

EOF

# 2. Start Generating Universal Baseline
cat > "$BASELINE_FILE" <<EOF
# Universal Baseline — Agent Skills
<!-- AUTO-GENERATED -->
<!-- Source SHA: $SOURCE_SHA -->
<!-- Last updated: $TIMESTAMP -->
<!-- Regenerate: make publish-baseline -->

EOF

render_nakomi_for_embed >> "$BASELINE_FILE"
echo "" >> "$BASELINE_FILE"

# Append constraints to baseline
cat "$CONSTRAINTS_FILE" >> "$BASELINE_FILE"
echo "" >> "$BASELINE_FILE"
echo "---" >> "$BASELINE_FILE"
echo "" >> "$BASELINE_FILE"

# 3. Build AGENTS.md by combining parts
render_nakomi_for_embed >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Include the full constraints rail in AGENTS.md (agents were missing PR metadata rules).
sed -n '/## 1)/,$p' "$CONSTRAINTS_FILE" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Skill Table Generation
extract_skill() {
    local skill_file="$1"
    local skill_dir_name
    skill_dir_name="$(basename "$(dirname "$skill_file")")"
    local frontmatter
    frontmatter="$(awk 'NR==1 && $0=="---"{inside=1; next} inside && $0=="---"{exit} inside{print}' "$skill_file")"
    local name
    name="$(printf '%s\n' "$frontmatter" | awk '
        /^name:[[:space:]]*/{
            line=$0
            sub(/^name:[[:space:]]*/, "", line)
            gsub(/^["'"'"']|["'"'"']$/, "", line)
            print line
            exit
        }
    ')"
    if [[ -z "$name" ]]; then
        name="$skill_dir_name"
    fi
    
    # Description: try to extract quoted description first
    local desc
    desc="$(printf '%s\n' "$frontmatter" | awk '
        BEGIN {capturing=0}
        /^description:[[:space:]]*/ {
            line=$0
            sub(/^description:[[:space:]]*/, "", line)
            if (line ~ /^(\||>)/) {
                capturing=1
                next
            }
            gsub(/^["'"'"']|["'"'"']$/, "", line)
            print line
            exit
        }
        capturing {
            if ($0 ~ /^[A-Za-z0-9_-]+:[[:space:]]*/) exit
            line=$0
            sub(/^[[:space:]]+/, "", line)
            if (length(line) > 0) printf "%s ", line
        }
        END {
            if (capturing) print ""
        }
    ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "$desc" || "$desc" == "|" || "$desc" == ">" ]]; then
         desc=$(awk '/^description:/{flag=1; next} /^[a-zA-Z0-9_-]+:/{flag=0} /^---/{flag=0} flag' "$skill_file" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-160 || echo "")
    fi
    if [[ -z "$desc" ]]; then
         desc=$(grep -v "^---" "$skill_file" | grep -v "^#" | grep -v "^$" | head -1 | cut -c1-160 || echo "")
    fi

    local tags
    tags="$(printf '%s\n' "$frontmatter" | awk '
        /^tags:[[:space:]]*/{
            line=$0
            sub(/^tags:[[:space:]]*/, "", line)
            gsub(/^\[|\]$/, "", line)
            print line
            exit
        }
    ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    
    # Example
    local example=$(grep -E "^\s*(bd |dx-|/skill )" "$skill_file" | grep -v "bd sync" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-60 || echo "")
    if [[ -z "$example" ]]; then
        example="—"
    else
        example="\`$example\`"
    fi

    echo "| **$name** | $desc | $example | $tags |"
}

generate_table() {
    local title="$1"
    shift
    local buffer=""
    buffer="## $title\n\n| Skill | Description | Example | Tags |\n|-------|-------------|---------|------|\n"

    for category in "$@"; do
        if [[ -d "$REPO_ROOT/$category" ]]; then
            while read -r skill; do
                buffer+="$(extract_skill "$skill")\n"
            done < <(find "$REPO_ROOT/$category" -maxdepth 2 -name "SKILL.md" | sort)
        fi
    done
    
    echo -e "$buffer" >> "$OUTFILE"
    echo -e "$buffer" >> "$BASELINE_FILE"
}

# 4. Generate Tables (to both files)
generate_table "Core Workflows" "core"
echo "" >> "$OUTFILE"; echo "" >> "$BASELINE_FILE"
generate_table "Extended Workflows" "extended"
echo "" >> "$OUTFILE"; echo "" >> "$BASELINE_FILE"
generate_table "Health & Monitoring" "health"
echo "" >> "$OUTFILE"; echo "" >> "$BASELINE_FILE"
generate_table "Infrastructure" "infra" "dispatch"
echo "" >> "$OUTFILE"; echo "" >> "$BASELINE_FILE"
generate_table "Railway Deployment" "railway"

# Footer
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"
cat >> "$OUTFILE" <<EOF

## Skill Discovery
**Auto-loaded from:** \`~/agent-skills/{core,extended,health,infra,railway,dispatch}/*/SKILL.md\`
**Specification**: https://agentskills.io/specification

**Regenerate this index:**
\`\`\`bash
make publish-baseline
\`\`\`

**Add new skill:**
1. Create \`~/agent-skills/<category>/<skill-name>/SKILL.md\`
2. Run \`make publish-baseline\`
EOF

# Append footer to baseline too
cat >> "$BASELINE_FILE" <<EOF

---
**Discovery**: Skills auto-load from \`~/agent-skills/{core,extended,health,infra,railway,dispatch}/*/SKILL.md\`
**Details**: Each skill's SKILL.md contains full documentation
**Specification**: https://agentskills.io/specification
**Source**: Generated from agent-skills commit shown in header
EOF

# Validation
LINES=$(wc -l < "$OUTFILE")
echo "✅ Generated $OUTFILE ($LINES lines)"
echo "✅ Generated $BASELINE_FILE"
echo "✅ Generated $CONSTRAINTS_FILE"

verify_nakomi_generation "$OUTFILE"
verify_nakomi_generation "$BASELINE_FILE"
echo "✅ Verified Nakomi policy presence in generated outputs"

if [[ $LINES -gt 800 ]]; then
    echo "⚠️  WARNING: AGENTS.md exceeds 800 lines ($LINES)"
fi
