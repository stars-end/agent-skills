#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OUTFILE="$REPO_ROOT/AGENTS.md"
DIST_DIR="$REPO_ROOT/dist"
BASELINE_FILE="$DIST_DIR/universal-baseline.md"
CONSTRAINTS_FILE="$DIST_DIR/dx-global-constraints.md"
SOURCE_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
mkdir -p "$DIST_DIR"

# 1. Generate Global Constraints (Layer A subset)
cat > "$CONSTRAINTS_FILE" <<EOF
# DX Global Constraints (V8.3)
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

## 2) V8 DX Automation Rules
1. **No auto-merge**: never enable auto-merge on PRs — humans merge
2. **No PR factory**: one PR per meaningful unit of work
3. **No canonical writes**: always use worktrees
4. **Feature-Key mandatory**: every commit needs \`Feature-Key: bd-<beads-id>\`

## 3) PR Metadata Rules (Blocking In CI)
- **PR title must include a Feature-Key**: include \`bd-<beads-id>\` somewhere in the title (e.g. \`bd-f6fh: ...\`)
- **PR body must include Agent**: add a line like \`Agent: <agent-id>\`

## 4) Delegation Rule (V8.3 - Batch by Outcome)
- **Primary rule**: batch by outcome, not by file. One agent per coherent change set.
- **Default parallelism**: 2 agents, scale to 3-4 only when independent and stable.
- **Do not delegate**: security-sensitive changes, architectural decisions, or high-blast-radius refactors.
- **Orchestrator owns outcomes**: review diffs, run validation, commit/push with required trailers.
- **See Section 6** for detailed parallel orchestration patterns.

## 5) Secrets + Env Sources (V8.3 - Railway Context Mandatory)
- **Railway shell is MANDATORY for dev work**: provides \`RAILWAY_SERVICE_FRONTEND_URL\`, \`RAILWAY_SERVICE_BACKEND_URL\`, and all env vars.
- **API keys**: \`op://dev/Agent-Secrets-Production/<FIELD>\` (transitional, see SECRETS_INDEX.md).
- **Railway CLI token**: \`op://dev/Railway-Delivery/token\` for CI/automation.
- **Quick reference**: use the \`op-secrets-quickref\` skill.

## 6) Parallel Agent Orchestration (V8.3)

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

**Primary: OpenCode (headless + server)**

\`\`\`bash
# Headless single-run lane
opencode run -m zai-coding-plan/glm-5 "Implement task T1 from plan.md"

# Server lane for parallel clients
opencode serve --hostname 127.0.0.1 --port 4096
opencode run --attach http://127.0.0.1:4096 -m zai-coding-plan/glm-5 "Implement task T2 from plan.md"
\`\`\`

**Reliability backstop: cc-glm-job.sh (governed fallback lane)**

\`\`\`bash
# Start a governed fallback job
CC_GLM_MODEL=glm-5 cc-glm-job.sh start --beads bd-xxx --prompt-file /tmp/p.prompt --pty

# Monitor fallback jobs
cc-glm-job.sh status --json
cc-glm-job.sh check --beads bd-xxx --json
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

**Cross-VM: dx-dispatch** (for remote execution only)

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
- \`~/agent-skills/extended/cc-glm/SKILL.md\`

Notes:
- PR metadata enforcement exists to keep squash merges ergonomic.
- If unsure what to use for Agent, use platform id (see \`DX_AGENT_ID.md\`).
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

## Nakomi Agent Protocol
### Role
Support a startup founder balancing high-leverage technical work and family responsibilities.
### Core Constraints
- Do not make irreversible decisions without explicit instruction
- Do not expand scope unless asked
- Do not optimize for cleverness or novelty
- Do not assume time availability

EOF

# Append constraints to baseline
cat "$CONSTRAINTS_FILE" >> "$BASELINE_FILE"
echo "" >> "$BASELINE_FILE"
echo "---" >> "$BASELINE_FILE"
echo "" >> "$BASELINE_FILE"

# 3. Build AGENTS.md by combining parts
cat >> "$OUTFILE" <<EOF
## Nakomi Agent Protocol
### Role
Support a startup founder balancing high-leverage technical work and family responsibilities.
### Core Constraints
- Do not make irreversible decisions without explicit instruction
- Do not expand scope unless asked
- Do not optimize for cleverness or novelty
- Do not assume time availability

EOF

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
    local example=$(grep -E "^\s*(bd |dx-|/skill )" "$skill_file" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-60 || echo "")
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

if [[ $LINES -gt 800 ]]; then
    echo "⚠️  WARNING: AGENTS.md exceeds 800 lines ($LINES)"
fi
