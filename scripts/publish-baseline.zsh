#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OUTFILE="$REPO_ROOT/AGENTS.md"
DIST_DIR="$REPO_ROOT/dist"
BASELINE_FILE="$DIST_DIR/universal-baseline.md"
CONSTRAINTS_FILE="$DIST_DIR/dx-global-constraints.md"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
mkdir -p "$DIST_DIR"

# 1. Generate Global Constraints (Layer A subset)
cat > "$CONSTRAINTS_FILE" <<EOF
# DX Global Constraints (V8)
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

## 4) Delegation Rule (cc-glm)
- **Default**: delegate mechanical tasks estimated \< 1 hour to \`cc-glm\` (via \`dx-delegate\`).
- **Do not delegate**: security-sensitive changes, architectural decisions, or high-blast-radius refactors.
- **Orchestrator owns outcomes**: review diffs, run validation, commit/push with required trailers.

Notes:
- PR metadata enforcement exists to keep squash merges ergonomic (don’t rely on commit messages).
- If you’re unsure what to use for Agent, use your platform id (see \`DX_AGENT_ID.md\`).
EOF

# Header for AGENTS.md
cat > "$OUTFILE" <<EOF
# AGENTS.md — Agent Skills Index
<!-- AUTO-GENERATED -->
<!-- Last updated: $TIMESTAMP -->
<!-- Regenerate: make publish-baseline -->

EOF

# 2. Start Generating Universal Baseline
cat > "$BASELINE_FILE" <<EOF
# Universal Baseline — Agent Skills
<!-- AUTO-GENERATED -->
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
    local name=$(grep "^name:" "$skill_file" | head -1 | cut -d: -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
    
    # Description: try to extract quoted description first
    local desc=$(grep "^description:" "$skill_file" | head -1 | sed 's/^description: *//' | sed 's/^"//' | sed 's/"$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
    if [[ -z "$desc" || "$desc" == "|" || "$desc" == ">" ]]; then
         desc=$(awk '/^description:/{flag=1; next} /^[a-z]+:/{flag=0} /^---/{flag=0} flag' "$skill_file" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-100 || echo "")
    fi
    if [[ -z "$desc" ]]; then
         desc=$(grep -v "^---" "$skill_file" | grep -v "^#" | grep -v "^$" | head -1 | cut -c1-100 || echo "")
    fi

    local tags=$(grep "^tags:" "$skill_file" | head -1 | cut -d: -f2- | tr -d '[]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
    
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
generate_table "Infrastructure & Health" "health" "infra" "railway" "dispatch"

# Footer
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"
cat >> "$OUTFILE" <<EOF

## Skill Discovery
**Auto-loaded from:** \`~/agent-skills/{core,extended,health,infra,railway}/*/SKILL.md\`
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
**Discovery**: Skills auto-load from \`~/agent-skills/{core,extended,health,infra,railway}/*/SKILL.md\`  
**Details**: Each skill's SKILL.md contains full documentation  
**Specification**: https://agentskills.io/specification  
EOF

# Validation
LINES=$(wc -l < "$OUTFILE")
echo "✅ Generated $OUTFILE ($LINES lines)"
echo "✅ Generated $BASELINE_FILE"
echo "✅ Generated $CONSTRAINTS_FILE"

if [[ $LINES -gt 800 ]]; then
    echo "⚠️  WARNING: AGENTS.md exceeds 800 lines ($LINES)"
fi
