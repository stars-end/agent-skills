#!/bin/bash
# scripts/compile_agent_context.sh

compile_agent_context() {
    REPO_DIR="${1:-.}"
    GLOBAL_SRC="$HOME/agent-skills/AGENTS.md"
    LOCAL_SRC="$REPO_DIR/AGENTS.local.md"
    TARGET="$REPO_DIR/AGENTS.md"

    if [ ! -f "$LOCAL_SRC" ]; then
        # If no AGENTS.local.md, we assume this repo is not using the compiled context workflow
        # (or it is the source repo itself).
        # We fail silently/gracefully as per design.
        return 0
    fi

    if [ ! -f "$GLOBAL_SRC" ]; then
        echo "❌ Global AGENTS.md not found: $GLOBAL_SRC"
        return 1
    fi

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

    # Write header
    cat > "$TARGET" << EOF
<!-- AUTO-COMPILED AGENTS.md -->
<!-- global-hash:$GLOBAL_HASH local-hash:$LOCAL_HASH -->
<!-- Source: ~/agent-skills/AGENTS.md + ./AGENTS.local.md -->
<!-- DO NOT EDIT - edit AGENTS.local.md instead -->

EOF

    # Append Global Content
    cat "$GLOBAL_SRC" >> "$TARGET"
    
    # Append Local Content Section
    echo -e "\n\n---\n\n# REPO-SPECIFIC CONTEXT\n" >> "$TARGET"
    cat "$LOCAL_SRC" >> "$TARGET"

    echo "✅ Compiled: $TARGET (global:${GLOBAL_HASH:0:8} local:${LOCAL_HASH:0:8})"
}

# Execute function if script is run directly
compile_agent_context "$@"
