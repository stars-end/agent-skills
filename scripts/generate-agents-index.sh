set -euo pipefail

# Ensure we are in the repo root
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

OUTFILE="$REPO_ROOT/AGENTS.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')

# Header
cat > "$OUTFILE" <<EOF
# AGENTS.md — Agent Skills Index
<!-- AUTO-GENERATED from SKILL.md files -->
<!-- Last updated: $TIMESTAMP -->
<!-- DO NOT EDIT MANUALLY - Run: scripts/generate-agents-index.sh -->

EOF

# Nakomi protocol (static fragment or fallback)
if [[ -f "$REPO_ROOT/fragments/nakomi-protocol.md" ]]; then
    cat "$REPO_ROOT/fragments/nakomi-protocol.md" >> "$OUTFILE"
else
    # Fallback minimal protocol if fragment missing
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
fi

echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Canonical rules (static fragment or fallback)
if [[ -f "$REPO_ROOT/fragments/canonical-rules.md" ]]; then
    cat "$REPO_ROOT/fragments/canonical-rules.md" >> "$OUTFILE"
else
    # Fallback minimal rules
    cat >> "$OUTFILE" <<EOF
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
EOF
fi

echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Function to extract skill metadata
extract_skill() {
    local skill_file="$1"
    local name=$(grep "^name:" "$skill_file" | head -1 | cut -d: -f2- | xargs || echo "")
    # Description: try to extract quoted description first
    local desc=$(grep "^description:" "$skill_file" | head -1 | sed 's/^description: *//' | sed 's/^"//' | sed 's/"$//' | xargs || echo "")
    
    # If empty or looks like a block scalar (starts with | or >), try awk but stop at next key
    if [[ -z "$desc" || "$desc" == "|" || "$desc" == ">" ]]; then
         desc=$(awk '/^description:/{flag=1; next} /^[a-z]+:/{flag=0} /^---/{flag=0} flag' "$skill_file" | tr '\n' ' ' | sed 's/  */ /g' | xargs | cut -c1-100 || echo "")
    fi
    
    # Fallback: look for first paragraph
    if [[ -z "$desc" || "$desc" == "|" || "$desc" == ">" ]]; then
         desc=$(grep -v "^---" "$skill_file" | grep -v "^#" | grep -v "^$" | head -1 | cut -c1-100 || echo "")
    fi

    local tags=$(grep "^tags:" "$skill_file" | head -1 | cut -d: -f2- | tr -d '[]' | xargs || echo "")
    
    # Extract first example command (if exists)
    # Look for code blocks or indented lines after Example header
    local example=""
    # Try to find a line starting with `bd ` or `dx-` or `/skill` inside the file
    example=$(grep -E "^\s*(bd |dx-|/skill )" "$skill_file" | head -1 | xargs | cut -c1-60 || echo "")
    
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
    # Remaining args are categories
    
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

# Core Workflows
generate_table "Core Workflows" "core"

# Extended Workflows
echo "" >> "$OUTFILE"
generate_table "Extended Workflows" "extended"

# Infrastructure & Health
echo "" >> "$OUTFILE"
generate_table "Infrastructure & Health" "health" "infra" "railway" "dispatch"

# Footer
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"
cat >> "$OUTFILE" <<'EOF'

## Skill Discovery

**Auto-loaded from:**
- \`~/agent-skills/core/*/SKILL.md\` - Core workflows
- \`~/agent-skills/extended/*/SKILL.md\` - Extended workflows
- \`~/agent-skills/health/*/SKILL.md\` - Health checks
- \`~/agent-skills/infra/*/SKILL.md\` - Infrastructure
- \`~/agent-skills/railway/*/SKILL.md\` - Deployment
- \`~/agent-skills/dispatch/*/SKILL.md\` - Cross-VM execution

**Full documentation:** Each SKILL.md contains detailed implementation, examples, and troubleshooting.

**Regenerate this index:**
\`\`\`bash
~/agent-skills/scripts/generate-agents-index.sh
\`\`\`

**Add new skill:**
1. Create \`~/agent-skills/<category>/<skill-name>/SKILL.md\`
2. Add frontmatter: \`name:\`, \`description:\`, \`tags:\`
3. Regenerate index (auto-triggered on commit via post-commit hook)
EOF

# Enforce <800 line limit
LINES=$(wc -l < "$OUTFILE")
echo "✅ Generated $OUTFILE ($LINES lines)"

if [[ $LINES -gt 800 ]]; then
    echo "⚠️  WARNING: AGENTS.md exceeds 800 lines ($LINES)"
    echo "   Consider reducing skill descriptions or consolidating."
    # We don't exit 1 here to avoid breaking builds, but we warn loudly.
fi
