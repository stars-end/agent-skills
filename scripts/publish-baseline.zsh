#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

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
CONSTRAINTS_SOURCE="$REPO_ROOT/fragments/dx-global-constraints.md"
if [[ ! -f "$CONSTRAINTS_SOURCE" ]]; then
    echo "ERROR: missing constraints source: $CONSTRAINTS_SOURCE" >&2
    exit 1
fi
cp "$CONSTRAINTS_SOURCE" "$CONSTRAINTS_FILE"

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

cat >> "$OUTFILE" <<'EOF'
## Repo Memory Maps

For brownfield work in this repo, read the curated repo-owned maps before
designing or editing:

- `docs/architecture/BROWNFIELD_MAP.md`
- `docs/architecture/DATA_AND_STORAGE.md`
- `docs/architecture/README.md`
- `docs/architecture/WORKFLOWS_AND_PATTERNS.md`

Use `dx-repo-memory-check --repo .` to validate map freshness.

---

EOF

# Skill Table Generation
extract_skill() {
    local skill_file="$1"
    local skill_dir_name
    skill_dir_name="$(basename "$(dirname "$skill_file")")"
    local frontmatter
    frontmatter="$(awk '$0=="---" && !inside{inside=1; next} inside && $0=="---"{exit} inside{print}' "$skill_file")"
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
    ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "$desc" || "$desc" == "|" || "$desc" == ">" ]]; then
         desc=$(awk '/^description:/{flag=1; next} /^[a-zA-Z0-9_-]+:/{flag=0} /^---/{flag=0} flag' "$skill_file" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
    fi
    if [[ -z "$desc" ]]; then
         desc=$(grep -v "^---" "$skill_file" | grep -v "^#" | grep -v "^$" | head -1 || echo "")
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

grep -q "Semantic mixed-health rule" "$OUTFILE"
grep -q "semantic_index_missing" "$OUTFILE"
grep -q "llm-tldr semantic degraded" "$OUTFILE"
grep -q "Semantic mixed-health rule" "$BASELINE_FILE"
grep -q "semantic_index_missing" "$BASELINE_FILE"
grep -q "llm-tldr semantic degraded" "$BASELINE_FILE"
grep -q "Semantic mixed-health rule" "$CONSTRAINTS_FILE"
grep -q "semantic_index_missing" "$CONSTRAINTS_FILE"
grep -q "llm-tldr semantic degraded" "$CONSTRAINTS_FILE"
echo "✅ Verified llm-tldr semantic mixed-health policy in generated outputs"

if [[ $LINES -gt 800 ]]; then
    echo "⚠️  WARNING: AGENTS.md exceeds 800 lines ($LINES)"
fi
