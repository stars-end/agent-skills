#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OUTFILE="$REPO_ROOT/dist/universal-baseline.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
COMMIT_SHA=$(git rev-parse HEAD)

mkdir -p "$REPO_ROOT/dist"

# Extract YAML frontmatter from SKILL.md
extract_frontmatter() {
    local skill_file=$1
    awk '/^---$/{if(++count==2) exit; next} count==1' "$skill_file"
}

# Parse YAML field from frontmatter (FIX 1: stdin piping + FIX 2: dotted paths)
parse_yaml_field() {
    local field=$1
    python3 - "$field" <<'PY'
import sys
import yaml

field = sys.argv[1]
fm_text = sys.stdin.read()

try:
    data = yaml.safe_load(fm_text) or {}
    
    # Support dotted paths (e.g., "metadata.display_example")
    def get_path(obj, path):
        parts = path.split(".")
        current = obj
        for part in parts:
            if not isinstance(current, dict):
                return ""
            current = current.get(part, "")
        return current
    
    value = get_path(data, field)
    
    # Format output
    if isinstance(value, list):
        print(",".join(str(x) for x in value))
    elif isinstance(value, dict):
        print("")  # Dicts need subfield queries
    else:
        print(str(value) if value else "")
except Exception:
    print("")
PY
}

# Header
cat > "$OUTFILE" <<EOF
# Universal Baseline — Agent Skills
<!-- AUTO-GENERATED -->
<!-- Source SHA: $COMMIT_SHA -->
<!-- Last updated: $TIMESTAMP -->
<!-- Regenerate: make publish-baseline -->

EOF

# Layer A: Operating Contract (curated)
echo "## Operating Contract (Layer A — Curated)" >> "$OUTFILE"
echo "" >> "$OUTFILE"

for fragment in nakomi-protocol canonical-rules beads-external-db session-start landing-the-plane v7.6-mechanisms; do
    if [[ -f "$REPO_ROOT/fragments/$fragment.md" ]]; then
        cat "$REPO_ROOT/fragments/$fragment.md" >> "$OUTFILE"
        echo "" >> "$OUTFILE"
    fi
done

echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Layer B: Universal Skill Index (generated)
echo "## Universal Skill Index (Layer B — Generated)" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Generate skill table (CORRECTED: stdin piping + dotted paths + deterministic sort)
generate_skill_table() {
    local category=$1
    local title=$2
    local temp_rows=$(mktemp)
    
    echo "### $title" >> "$OUTFILE"
    echo "" >> "$OUTFILE"
    echo "| Skill | Description | Example | Tags |" >> "$OUTFILE"
    echo "|-------|-------------|---------|------|" >> "$OUTFILE"
    
    for skill_dir in "$REPO_ROOT/$category"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_file="${skill_dir}SKILL.md"
        [[ -f "$skill_file" ]] || continue
        
        # Extract frontmatter once
        fm=$(extract_frontmatter "$skill_file")
        
        # Parse fields using stdin piping (CORRECTED)
        name=$(printf '%s' "$fm" | parse_yaml_field "name" | cut -c1-30)
        desc=$(printf '%s' "$fm" | parse_yaml_field "description" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-60)
        
        # Parse nested metadata fields directly (CORRECTED)
        example=$(printf '%s' "$fm" | parse_yaml_field "metadata.display_example" | cut -c1-40)
        [[ -z "$example" ]] && example="See SKILL.md"
        
        tags=$(printf '%s' "$fm" | parse_yaml_field "metadata.display_tags")
        # Fallback to top-level tags during migration
        [[ -z "$tags" ]] && tags=$(printf '%s' "$fm" | parse_yaml_field "tags")
        
        # Write to temp file for deterministic sorting
        echo "| $name | $desc | \`$example\` | $tags |" >> "$temp_rows"
    done
    
    # Sort THEN append (determinism)
    sort "$temp_rows" >> "$OUTFILE"
    rm "$temp_rows"
    
    echo "" >> "$OUTFILE"
}

# Generate tables
generate_skill_table "core" "Core Workflows"
generate_skill_table "extended" "Extended Workflows"
generate_skill_table "health" "Health & Monitoring"
generate_skill_table "infra" "Infrastructure"
generate_skill_table "railway" "Railway Deployment"

# Footer
cat >> "$OUTFILE" <<'EOF'

---

**Discovery**: Skills auto-load from `~/agent-skills/{core,extended,health,infra,railway}/*/SKILL.md`  
**Details**: Each skill's SKILL.md contains full documentation  
**Specification**: https://agentskills.io/specification  
**Source**: Generated from agent-skills commit shown in header
EOF

# Publish tiny global constraints rail
CONSTRAINTS_SRC="$REPO_ROOT/fragments/dx-global-constraints.md"
CONSTRAINTS_DST="$REPO_ROOT/dist/dx-global-constraints.md"
if [[ -f "$CONSTRAINTS_SRC" ]]; then
    cp "$CONSTRAINTS_SRC" "$CONSTRAINTS_DST"
    echo "✅ Published constraints: $CONSTRAINTS_DST"
else
    echo "⚠️  Warning: dx-global-constraints.md not found"
fi

LINES=$(wc -l < "$OUTFILE")
echo "✅ Published baseline: $OUTFILE ($LINES lines, SHA: ${COMMIT_SHA:0:8})"

if [[ $LINES -gt 800 ]]; then
    echo "⚠️  Warning: Baseline is $LINES lines (goal: <800, not blocking)"
fi
