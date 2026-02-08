#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OUTFILE="$REPO_ROOT/AGENTS.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')

# Header
cat > "$OUTFILE" <<EOF
# AGENTS.md — Agent Skills Index
<!-- AUTO-GENERATED -->
<!-- Last updated: $TIMESTAMP -->
<!-- Regenerate: make publish-baseline -->

EOF

# Static V8 Content (formerly fragments)
cat >> "$OUTFILE" <<EOF
## Nakomi Agent Protocol
### Role
Support a startup founder balancing high-leverage technical work and family responsibilities.
### Core Constraints
- Do not make irreversible decisions without explicit instruction
- Do not expand scope unless asked
- Do not optimize for cleverness or novelty
- Do not assume time availability

## Canonical Repository Rules
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

## V8 DX Automation Rules
1. **No auto-merge**: never enable auto-merge on PRs — humans merge
2. **No PR factory**: one PR per meaningful unit of work
3. **No canonical writes**: always use worktrees
4. **Feature-Key mandatory**: every commit needs \`Feature-Key: bd-XXXX\`

EOF

echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Skill Table Generation
extract_skill() {
    local skill_file="$1"
    local name=$(grep "^name:" "$skill_file" | head -1 | cut -d: -f2- | xargs || echo "")
    
    # Description: try to extract quoted description first
    local desc=$(grep "^description:" "$skill_file" | head -1 | sed 's/^description: *//' | sed 's/^"//' | sed 's/"$//' | xargs || echo "")
    if [[ -z "$desc" || "$desc" == "|" || "$desc" == ">" ]]; then
         desc=$(awk '/^description:/{flag=1; next} /^[a-z]+:/{flag=0} /^---/{flag=0} flag' "$skill_file" | tr '\n' ' ' | sed 's/  */ /g' | xargs | cut -c1-100 || echo "")
    fi
    if [[ -z "$desc" ]]; then
         desc=$(grep -v "^---" "$skill_file" | grep -v "^#" | grep -v "^$" | head -1 | cut -c1-100 || echo "")
    fi

    local tags=$(grep "^tags:" "$skill_file" | head -1 | cut -d: -f2- | tr -d '[]' | xargs || echo "")
    
    # Example
    local example=$(grep -E "^\s*(bd |dx-|/skill )" "$skill_file" | head -1 | xargs | cut -c1-60 || echo "")
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
    echo "## $title" >> "$OUTFILE"
    echo "" >> "$OUTFILE"
    echo "| Skill | Description | Example | Tags |" >> "$OUTFILE"
    echo "|-------|-------------|---------|------|" >> "$OUTFILE"

    for category in "$@"; do
        if [[ -d "$REPO_ROOT/$category" ]]; then
            find "$REPO_ROOT/$category" -maxdepth 2 -name "SKILL.md" | sort | while read -r skill; do
                extract_skill "$skill" >> "$OUTFILE"
            done
        fi
    done
}

# Generate Tables
generate_table "Core Workflows" "core"
echo "" >> "$OUTFILE"
generate_table "Extended Workflows" "extended"
echo "" >> "$OUTFILE"
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

# Validation
LINES=$(wc -l < "$OUTFILE")
echo "✅ Generated $OUTFILE ($LINES lines)"
if [[ $LINES -gt 800 ]]; then
    echo "⚠️  WARNING: AGENTS.md exceeds 800 lines ($LINES)"
fi
