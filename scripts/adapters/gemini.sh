#!/usr/bin/env bash
# gemini adapter for dx-runner
#
# Implements the adapter contract for Google Gemini CLI
# (Future capacity - basic implementation)
#
# Required functions:
#   adapter_start        - Start a job
#   adapter_check        - Check health state  
#   adapter_stop         - Stop a job
#   adapter_preflight    - Provider-specific preflight
#   adapter_probe_model  - Test model availability
#   adapter_list_models  - List available models

adapter_find_gemini() {
    for candidate in "gemini" "gemini-cli" "/usr/local/bin/gemini"; do
        if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

adapter_preflight() {
    local errors=0
    
    # Check 1: Gemini binary
    echo -n "gemini binary: "
    local gemini_bin
    gemini_bin="$(adapter_find_gemini)"
    if [[ -n "$gemini_bin" ]]; then
        echo "OK ($gemini_bin)"
    else
        echo "MISSING"
        echo "  ERROR: gemini CLI not found"
        echo "  Install: npm install -g @anthropic/gemini-cli (or equivalent)"
        errors=$((errors + 1))
    fi
    
    # Check 2: API key
    echo -n "api key: "
    if [[ -n "${GEMINI_API_KEY:-}" || -n "${GOOGLE_API_KEY:-}" ]]; then
        echo "OK (env var set)"
    else
        echo "MISSING"
        echo "  ERROR: GEMINI_API_KEY or GOOGLE_API_KEY not set"
        errors=$((errors + 1))
    fi
    
    return $errors
}

adapter_start() {
    local beads="$1"
    local prompt_file="$2"
    local worktree="$3"
    local log_file="$4"
    
    local gemini_bin
    gemini_bin="$(adapter_find_gemini)" || {
        echo "ERROR: gemini not found" >&2
        return 1
    }
    
    local model="${GEMINI_MODEL:-gemini-2.0-flash}"
    
    echo "[gemini-adapter] START beads=$beads model=$model" >> "$log_file"
    
    local prompt
    prompt="$(cat "$prompt_file")"
    
    local cmd_args=("$gemini_bin")
    
    # Add model flag if supported
    if "$gemini_bin" --help 2>/dev/null | grep -q -- "--model"; then
        cmd_args+=(--model "$model")
    fi
    
    # Add worktree as cwd if specified
    if [[ -n "$worktree" && -d "$worktree" ]]; then
        cmd_args+=(--cwd "$worktree")
    fi
    
    nohup "${cmd_args[@]}" "$prompt" >> "$log_file" 2>&1 &
    echo $!
}

adapter_probe_model() {
    local model="${1:-gemini-2.0-flash}"
    local gemini_bin
    gemini_bin="$(adapter_find_gemini)" || return 1
    
    # Quick probe
    timeout 30 "$gemini_bin" --model "$model" "Return READY" 2>/dev/null | grep -q "READY" || return 1
    
    return 0
}

adapter_list_models() {
    echo "gemini-1.5-flash"
    echo "gemini-1.5-pro"
    echo "gemini-2.0-flash"
    echo "gemini-2.0-pro"
}

adapter_stop() {
    local pid="$1"
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null || true
    fi
}
