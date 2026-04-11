#!/bin/bash
# scripts/dx-check.sh
# Unified bootstrap command: Check health + Auto-fix.

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

detect_dx_runtime() {
    if [[ -n "${DX_CHECK_RUNTIME:-}" ]]; then
        echo "$DX_CHECK_RUNTIME"
        return
    fi

    local candidates=()
    command -v codex >/dev/null 2>&1 && candidates+=("codex")
    command -v claude >/dev/null 2>&1 && candidates+=("claude")
    command -v opencode >/dev/null 2>&1 && candidates+=("opencode")
    command -v gemini >/dev/null 2>&1 && candidates+=("gemini")

    if [[ "${#candidates[@]}" -eq 1 ]]; then
        echo "${candidates[0]}"
        return
    fi

    if [[ "${#candidates[@]}" -gt 1 ]]; then
        echo "__ambiguous__:${candidates[*]}"
        return
    fi

    echo ""
}

runtime_mcp_list_cmd() {
    local runtime="$1"
    case "$runtime" in
        codex) echo "codex mcp list" ;;
        claude) echo "claude mcp list" ;;
        opencode) echo "opencode mcp list" ;;
        gemini) echo "gemini mcp list" ;;
        *) return 1 ;;
    esac
}

runtime_tool_visible() {
    local runtime="$1"
    local tool="$2"
    local out="$3"

    case "$runtime" in
        codex)
            echo "$out" | rg -q "^${tool}[[:space:]].*enabled"
            ;;
        claude)
            echo "$out" | rg -q "${tool}: .*Connected"
            ;;
        opencode)
            echo "$out" | rg -q "${tool} .*connected"
            ;;
        gemini)
            echo "$out" | rg -q "${tool}: .*Connected"
            ;;
        *)
            return 1
            ;;
    esac
}

check_codex_thread_surface() {
    local helper="${SCRIPT_DIR}/dx-codex-thread-surface-check.sh"
    [[ -x "$helper" ]] || return 0

    local out status reason missing observed thread_id
    out="$("$helper" "$(pwd)")"
    status="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
    reason="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("reason",""))')"

    case "$status" in
        pass)
            echo -e "${GREEN}✅ Codex thread-surface check passed: llm-tldr + serena present in recent thread state${RESET}"
            return 0
            ;;
        skip)
            echo -e "${YELLOW}⚠️  Codex thread-surface check skipped (${reason}).${RESET}"
            return 0
            ;;
        fail)
            missing="$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(d.get("missing",[])))')"
            observed="$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(",".join(d.get("observed",[])))')"
            thread_id="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("thread_id",""))')"
            echo -e "${RED}❌ Codex thread-surface check failed: recent thread state is missing required MCP tools:${missing}${RESET}"
            echo "   Thread: ${thread_id}"
            echo "   Observed dynamic tools: ${observed:-<none>}"
            echo "   Diagnosis: codex mcp list can be green while the live thread tool surface is still missing llm-tldr/serena."
            echo "   Action: restart Codex, create a fresh thread in this workspace, and re-run dx-check."
            return 1
            ;;
        *)
            echo -e "${YELLOW}⚠️  Codex thread-surface check produced unexpected output; skipping.${RESET}"
            return 0
            ;;
    esac
}

check_active_runtime_mcp_exposure() {
    local runtime
    runtime="$(detect_dx_runtime)"

    if [[ "$runtime" == __ambiguous__:* ]]; then
        local options="${runtime#__ambiguous__:}"
        echo -e "${YELLOW}⚠️  MCP preflight skipped: active runtime is ambiguous (${options}).${RESET}"
        echo "   Set DX_CHECK_RUNTIME to one of: codex, claude, opencode, gemini"
        echo "   to enforce runtime-specific MCP preflight."
        return 0
    fi

    if [[ -z "$runtime" ]]; then
        echo -e "${YELLOW}⚠️  MCP preflight skipped: no supported runtime CLI found (codex/claude/opencode/gemini).${RESET}"
        return 0
    fi

    local cmd
    if ! cmd="$(runtime_mcp_list_cmd "$runtime")"; then
        echo -e "${RED}❌ MCP preflight failed: unsupported DX_CHECK_RUNTIME='$runtime'.${RESET}"
        echo "   Use one of: codex, claude, opencode, gemini"
        return 1
    fi

    if [[ -z "${DX_CHECK_RUNTIME:-}" ]]; then
        echo -e "${BLUE}🔎 Active-runtime MCP preflight (${runtime}, inferred single available runtime)...${RESET}"
    else
        echo -e "${BLUE}🔎 Active-runtime MCP preflight (${runtime}, explicit DX_CHECK_RUNTIME)...${RESET}"
    fi

    local out
    if ! out="$(eval "$cmd" 2>&1)"; then
        echo -e "${RED}❌ MCP preflight failed: could not run '$cmd'.${RESET}"
        echo "   Action: verify runtime CLI health and MCP startup; then rerun dx-check."
        return 1
    fi

    local missing=""
    for tool in llm-tldr serena; do
        if ! runtime_tool_visible "$runtime" "$tool" "$out"; then
            missing="$missing $tool"
        fi
    done

    if [[ -n "$missing" ]]; then
        echo -e "${RED}❌ MCP preflight failed (${runtime}): required tools not visible:${missing}${RESET}"
        echo "   Action: run Fleet Sync apply/repair, restart the ${runtime} runtime, and retry dx-check."
        return 1
    fi

    echo -e "${GREEN}✅ MCP preflight passed (${runtime}): llm-tldr + serena visible${RESET}"
    if [[ "$runtime" == "codex" ]]; then
        check_codex_thread_surface || return 1
    fi
    return 0
}

# Resolve symlinks to get actual script directory (works on macOS and Linux)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

echo -e "${BLUE}🩺 Running DX Health Check...${RESET}"

# V8.6 Preflight: prefer centralized epyc12 Dolt SQL via a dedicated runtime dir.
DEFAULT_BEADS_DIR="$HOME/.beads-runtime/.beads"
if [[ -z "${BEADS_DIR:-}" ]]; then
    if [[ -d "$DEFAULT_BEADS_DIR" ]]; then
        echo -e "${YELLOW}⚠️  BEADS_DIR not set; defaulting to ${DEFAULT_BEADS_DIR} for this run.${RESET}"
        echo "   Tip: persist with: export BEADS_DIR=\"$DEFAULT_BEADS_DIR\" (e.g. ~/.zshenv or ~/.bash_profile)"
        export BEADS_DIR="$DEFAULT_BEADS_DIR"
        export BEADS_IGNORE_REPO_MISMATCH=1
    else
        echo -e "${RED}❌ FATAL: BEADS_DIR not set and default DB not found.${RESET}"
        echo "   Expected Beads runtime at: $DEFAULT_BEADS_DIR"
        echo "   Action:"
        echo "     1) Create $DEFAULT_BEADS_DIR/metadata.json for epyc12 Dolt SQL"
        echo "     2) Persist: export BEADS_DIR=\"$DEFAULT_BEADS_DIR\""
        echo "     3) Persist: export BEADS_DOLT_SERVER_HOST=\"100.107.173.83\""
        exit 1
    fi
fi

# Ensure mismatch bypass is set if using centralized runtime
if [[ "${BEADS_DIR}" == "${DEFAULT_BEADS_DIR}" ]]; then
    export BEADS_IGNORE_REPO_MISMATCH=1
fi

# Dolt hub defaulting for plain `bd` usability (prevents localhost split-brain on spokes).
DEFAULT_BEADS_DOLT_SERVER_HOST="${EPYC12_BEADS_HOST:-100.107.173.83}"
DEFAULT_BEADS_DOLT_SERVER_PORT="${EPYC12_BEADS_PORT:-3307}"
if [[ -z "${BEADS_DOLT_SERVER_HOST:-}" ]]; then
    echo -e "${YELLOW}⚠️  BEADS_DOLT_SERVER_HOST not set; defaulting to ${DEFAULT_BEADS_DOLT_SERVER_HOST} for this run.${RESET}"
    echo "   Tip: persist with: export BEADS_DOLT_SERVER_HOST=\"${DEFAULT_BEADS_DOLT_SERVER_HOST}\" (e.g. ~/.zshenv)"
    export BEADS_DOLT_SERVER_HOST="${DEFAULT_BEADS_DOLT_SERVER_HOST}"
fi
if [[ -z "${BEADS_DOLT_SERVER_PORT:-}" ]]; then
    echo -e "${YELLOW}⚠️  BEADS_DOLT_SERVER_PORT not set; defaulting to ${DEFAULT_BEADS_DOLT_SERVER_PORT} for this run.${RESET}"
    echo "   Tip: persist with: export BEADS_DOLT_SERVER_PORT=\"${DEFAULT_BEADS_DOLT_SERVER_PORT}\" (e.g. ~/.zshenv)"
    export BEADS_DOLT_SERVER_PORT="${DEFAULT_BEADS_DOLT_SERVER_PORT}"
fi

if [[ -d ".beads" ]]; then
    echo -e "${YELLOW}⚠️  Encountered local .beads/ directory (DEPRECATED)${RESET}"
    echo "   V5 requires this to be removed. Deleting..."
    rm -rf .beads
fi

TRACKED_BEADS_FILES="$(git ls-files '.beads/**' 2>/dev/null || true)"
if [[ -n "$TRACKED_BEADS_FILES" ]]; then
    echo -e "${RED}❌ FATAL: repository is tracking local .beads files (deprecated).${RESET}"
    echo "   Remove from index:"
    echo "     git rm --cached -r .beads"
    echo "   Tracked paths:"
    echo "$TRACKED_BEADS_FILES" | sed 's/^/     - /'
    exit 1
fi

needs_fix=0

# macOS hygiene: disable legacy ru LaunchAgent if present (bd-f5rw)
if [[ "$(uname -s)" == "Darwin" ]]; then
    if launchctl print "gui/$(id -u)/io.agentskills.ru" >/dev/null 2>&1 || [[ -f "$HOME/Library/LaunchAgents/io.agentskills.ru.plist" ]]; then
        echo -e "${YELLOW}⚠️  Legacy ru LaunchAgent detected (io.agentskills.ru).${RESET}"
        if [[ "${DX_AUTO_DISABLE_RU_LAUNCHAGENT:-1}" == "1" ]]; then
            if "${SCRIPT_DIR}/dx-disable-ru-launchagent.sh"; then
                echo -e "${GREEN}✅ Disabled legacy ru LaunchAgent.${RESET}"
            else
                echo -e "${RED}❌ Failed to disable legacy ru LaunchAgent.${RESET}"
                needs_fix=1
            fi
        else
            echo "   Run: ${SCRIPT_DIR}/dx-disable-ru-launchagent.sh"
            needs_fix=1
        fi
    fi
fi

# Freshness Check for AGENTS.md
if [ -f "AGENTS.local.md" ]; then
    get_hash() {
        if command -v md5sum >/dev/null 2>&1; then
            md5sum "$1" | cut -d' ' -f1
        else
            md5 -q "$1"
        fi
    }

    GLOBAL_SRC=~/agent-skills/AGENTS.md
    if [ -f "$GLOBAL_SRC" ]; then
        GLOBAL_HASH=$(get_hash "$GLOBAL_SRC")
        LOCAL_HASH=$(get_hash "AGENTS.local.md")
        
        COMPILED_HASH=$(head -n 5 AGENTS.md 2>/dev/null | grep -o 'global-hash:[a-f0-9]*' | cut -d: -f2 || echo "none")
        COMPILED_LOCAL_HASH=$(head -n 5 AGENTS.md 2>/dev/null | grep -o 'local-hash:[a-f0-9]*' | cut -d: -f2 || echo "none")

        if [ "$GLOBAL_HASH" != "$COMPILED_HASH" ] || [ "$LOCAL_HASH" != "$COMPILED_LOCAL_HASH" ]; then
            echo -e "${BLUE}⚠️  AGENTS.md stale - recompiling...${RESET}"
            "${SCRIPT_DIR}/compile_agent_context.sh" .
        fi
    fi
fi

if ! "${SCRIPT_DIR}/dx-status.sh"; then
    needs_fix=1
fi

# Active Beads runtime must point at the centralized Dolt SQL service. The old
# ~/bd git mirror is legacy rollback state, not a durability gate.
if [[ "${BEADS_DIR}" == "${DEFAULT_BEADS_DIR}" ]]; then
    if [[ ! -f "$BEADS_DIR/metadata.json" || ! -f "$BEADS_DIR/config.yaml" ]]; then
        echo -e "${RED}❌ FATAL: BEADS_DIR points at $DEFAULT_BEADS_DIR but runtime metadata/config is missing.${RESET}"
        echo "   Fix: hydrate $DEFAULT_BEADS_DIR with epyc12 Dolt SQL metadata/config."
        needs_fix=1
    fi
fi

# WIP Branch Check
if [ -f "${SCRIPT_DIR}/dx-wip-check.sh" ]; then
    "${SCRIPT_DIR}/dx-wip-check.sh"
fi

if ! check_active_runtime_mcp_exposure; then
    needs_fix=1
fi

if [ "$needs_fix" -eq 0 ]; then
    echo -e "${GREEN}✨ Environment is healthy.${RESET}"
else
    echo -e "${RED}⚠️  Environment unhealthy.${RESET}"
    
    # Check for TTY or NO_PROMPT override
    if [ -t 0 ] && [ "${DX_CHECK_NO_PROMPT:-0}" != "1" ]; then
        read -p "Run auto-fix (hydrate)? [Y/n]: " run_fix
    else
        echo -e "${BLUE}ℹ Non-interactive mode detected. Auto-fixing...${RESET}"
        run_fix="y"
    fi

    if [[ $run_fix =~ ^[Yy] ]] || [[ -z $run_fix ]]; then
        "${SCRIPT_DIR}/dx-hydrate.sh"
        echo -e "${BLUE}🔄 Re-checking status...${RESET}"
        if ! "${SCRIPT_DIR}/dx-status.sh"; then
            exit 1
        fi
        if ! check_active_runtime_mcp_exposure; then
            exit 1
        fi
    else
        echo "Exiting without fix."
        exit 1
    fi
fi
