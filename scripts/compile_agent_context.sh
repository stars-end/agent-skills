#!/bin/bash
# scripts/compile_agent_context.sh
# Version: 2.1 (Dynamic Routing Table with Safe Python Embedding)

compile_agent_context() {
    REPO_DIR="${1:-.}"
    GLOBAL_SRC="$HOME/agent-skills/AGENTS.global.md"
    LOCAL_SRC="$REPO_DIR/AGENTS.local.md"
    CONTEXT_DIR="$REPO_DIR/.claude/skills"
    TARGET="$REPO_DIR/AGENTS.md"

    # Skip if no AGENTS.local.md (repo not opted in)
    if [ ! -f "$LOCAL_SRC" ]; then
        return 0
    fi

    if [ ! -f "$GLOBAL_SRC" ]; then
        echo "❌ Global AGENTS.global.md not found: $GLOBAL_SRC"
        return 1
    fi

    # Helper: Extract routing table using Python (std lib only)
    extract_skill_routing() {
        python3 - "$@" << 'PY_SCRIPT'
import sys, re, os
from pathlib import Path

def parse_skill(path):
    try:
        content = Path(path).read_text(encoding='utf-8')
        match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
        if not match: return None
        
        frontmatter = match.group(1)
        
        # Parse name
        name_m = re.search(r'^name:\s*(.+)$', frontmatter, re.MULTILINE)
        name = name_m.group(1).strip() if name_m else Path(path).parent.name
        
        # Parse activation (list)
        activation = []
        in_activation = False
        for line in frontmatter.splitlines():
            if line.startswith('activation:'):
                in_activation = True
                continue
            if in_activation:
                if line.strip().startswith('- '):
                    val = line.strip()[2:].strip("'\"")
                    activation.append(val)
                elif re.match(r'^\S', line): # Start of new key
                    in_activation = False
        
        # Parse purpose/description
        desc_m = re.search(r'^(description|purpose):\s*(.+)$', frontmatter, re.MULTILINE)
        desc = ''
        if desc_m:
            desc = desc_m.group(2).strip()
            if desc == '|': # YAML block scalar
                # Find the block content
                desc_idx = frontmatter.find(desc_m.group(0)) + len(desc_m.group(0))
                remaining = frontmatter[desc_idx:]
                lines = []
                for line in remaining.splitlines():
                    if not line.strip(): continue
                    if not line.startswith('  '): break
                    lines.append(line.strip())
                desc = ' '.join(lines)
        
        if not activation: return None
        
        return {
            'name': name,
            'activation': activation,
            'desc': desc[:60] + '...' if len(desc) > 60 else desc
        }
    except Exception as e:
        return None

print('| Activation Keywords | Skill | Purpose |')
print('|---------------------|-------|---------|')

paths = sys.argv[1:]
rows = []
for p in paths:
    if not os.path.isfile(p): continue
    data = parse_skill(p)
    if data:
        keywords = ', '.join(f'"{k}"' for k in data['activation'][:4])
        # Format: core/beads-workflow if in core, else just name if in context
        skill_ref = data['name']
        if '/core/' in p: skill_ref = f'core/{data["name"]}'
        elif '/safety/' in p: skill_ref = f'safety/{data["name"]}'
        elif '/dispatch/' in p: skill_ref = f'dispatch/{data["name"]}'
        elif '/health/' in p: skill_ref = f'health/{data["name"]}'
        elif '/railway/' in p: skill_ref = f'railway/{data["name"]}'
        
        rows.append(f'| {keywords} | {skill_ref} | {data["desc"]} |')

for r in sorted(rows):
    print(r)
PY_SCRIPT
    }

    # Extract routing tables
    # Global skills
    GLOBAL_SKILLS=$(find "$HOME/agent-skills/core" "$HOME/agent-skills/dispatch" "$HOME/agent-skills/safety" "$HOME/agent-skills/health" "$HOME/agent-skills/railway" -name "SKILL.md" 2>/dev/null)
    GLOBAL_ROUTING=$(extract_skill_routing $GLOBAL_SKILLS)

    # Context skills
    CONTEXT_ROUTING=""
    if [ -d "$CONTEXT_DIR" ]; then
        CONTEXT_SKILLS=$(find "$CONTEXT_DIR" -name "SKILL.md" 2>/dev/null)
        if [ -n "$CONTEXT_SKILLS" ]; then
            CONTEXT_ROUTING=$(extract_skill_routing $CONTEXT_SKILLS)
        fi
    fi

    # Compute hashes
    get_hash() {
        if command -v md5sum >/dev/null 2>&1;
        then
            md5sum "$1" | cut -d' ' -f1
        else
            md5 -q "$1"
        fi
    }

    GLOBAL_HASH=$(get_hash "$GLOBAL_SRC")
    LOCAL_HASH=$(get_hash "$LOCAL_SRC")
    
    CONTEXT_HASH="none"
    if [ -d "$CONTEXT_DIR" ]; then
        if command -v md5sum >/dev/null 2>&1;
        then
            CONTEXT_HASH=$(find "$CONTEXT_DIR" -name "SKILL.md" -exec cat {} \; 2>/dev/null | md5sum | cut -d' ' -f1)
        else
            CONTEXT_HASH=$(find "$CONTEXT_DIR" -name "SKILL.md" -exec cat {} \; 2>/dev/null | md5 -q)
        fi
    fi

    # Write compiled AGENTS.md
    cat > "$TARGET" << EOF
<!-- AUTO-COMPILED AGENTS.md -->
<!-- global-hash:$GLOBAL_HASH local-hash:$LOCAL_HASH context-hash:$CONTEXT_HASH -->
<!-- Source: ~/agent-skills/AGENTS.global.md + ./AGENTS.local.md + .claude/skills/context-*/ -->
<!-- DO NOT EDIT - edit AGENTS.local.md instead -->

# Skill Routing Table

## Global Skills
$GLOBAL_ROUTING

EOF

    if [ -n "$CONTEXT_ROUTING" ]; then
        cat >> "$TARGET" << EOF

## Repo Context Skills
$CONTEXT_ROUTING
EOF
    fi

    cat >> "$TARGET" << EOF

---

EOF

    cat "$GLOBAL_SRC" >> "$TARGET"
    
    # Append Local Content
    echo -e "\n\n---\n\n# REPO-SPECIFIC CONTEXT\n" >> "$TARGET"
    cat "$LOCAL_SRC" >> "$TARGET"

    echo "✅ Compiled: $TARGET"
}

compile_agent_context "$@"
