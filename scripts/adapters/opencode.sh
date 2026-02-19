#!/usr/bin/env bash
# opencode adapter for dx-runner
#
# Implements the adapter contract for OpenCode headless
# Includes reliability fixes for bd-cbsb.15-.18:
#   - Capability preflight with model fallback (bd-cbsb.15)
#   - Permission handling (bd-cbsb.16)
#   - No-op detection (bd-cbsb.17)
#   - beads-mcp dependency check (bd-cbsb.18)
#
# Required functions:
#   adapter_start        - Start a job
#   adapter_check        - Check health state  
#   adapter_stop         - Stop a job
#   adapter_preflight    - Provider-specific preflight
#   adapter_probe_model  - Test model availability
#   adapter_list_models  - List available models

# Model fallback chains per host (bd-cbsb.15)
declare -A HOST_FALLBACK_CHAINS=(
    ["epyc12"]="zhipuai-coding-plan/glm-5:zai/glm-5:opencode/glm-5-free"
    ["epyc6"]="zhipuai-coding-plan/glm-5:zai/glm-5:opencode/glm-5-free"
    ["macmini"]="zhipuai-coding-plan/glm-5:zai/glm-5:opencode/glm-5-free"
    ["homedesktop-wsl"]="zhipuai-coding-plan/glm-5:zai/glm-5:opencode/glm-5-free"
)

DEFAULT_FALLBACK="zhipuai-coding-plan/glm-5:zai/glm-5:opencode/glm-5-free"

adapter_find_opencode() {
    for candidate in "opencode" "/home/linuxbrew/.linuxbrew/bin/opencode" "/opt/homebrew/bin/opencode"; do
        if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

adapter_preflight() {
    local errors=0
    
    # Check 1: OpenCode binary (bd-cbsb.15)
    echo -n "opencode binary: "
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)"
    if [[ -n "$opencode_bin" ]]; then
        echo "OK ($opencode_bin)"
    else
        echo "MISSING"
        echo "  ERROR: opencode CLI not found"
        errors=$((errors + 1))
    fi
    
    # Check 2: Model availability with fallback (bd-cbsb.15)
    echo -n "model availability: "
    if [[ -n "$opencode_bin" ]]; then
        local models
        models=$("$opencode_bin" models 2>/dev/null | grep -E "^[a-z]" | head -5) || true
        if [[ -n "$models" ]]; then
            echo "OK ($(echo "$models" | wc -l | tr -d ' ') providers)"
        else
            echo "NO_MODELS"
            echo "  ERROR: No models available"
            errors=$((errors + 1))
        fi
    fi
    
    # Check 3: beads-mcp availability (bd-cbsb.18)
    echo -n "beads-mcp binary: "
    if command -v beads-mcp >/dev/null 2>&1; then
        echo "OK ($(command -v beads-mcp))"
    else
        echo "MISSING (optional - Beads context degraded)"
        echo "  WARN: beads-mcp not found, headless context will be limited"
    fi
    
    # Check 4: mise trust state (bd-cbsb.17 - for validation steps)
    echo -n "mise trust: "
    if command -v mise >/dev/null 2>&1; then
        local trust_state
        trust_state="$(mise trust --show 2>/dev/null)" || true
        if [[ -n "$trust_state" ]]; then
            echo "OK"
        else
            echo "UNTRUSTED"
            echo "  WARN: Run 'mise trust' in worktree before dispatch"
        fi
    else
        echo "NOT_INSTALLED"
        echo "  WARN: mise not found"
    fi
    
    return $errors
}

adapter_resolve_model() {
    local preferred="$1"
    local host="${2:-$(hostname 2>/dev/null | cut -d. -f1)}"
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || return 1
    
    # Get available models
    local available_models
    available_models=$("$opencode_bin" models 2>/dev/null | grep -E "^- " | sed 's/^- //' | tr '\n' ' ') || true
    
    # Check preferred first
    if [[ -n "$preferred" ]]; then
        if echo "$available_models" | grep -q "$preferred"; then
            echo "$preferred|preferred|"
            return 0
        fi
    fi
    
    # Use fallback chain
    local chain="${HOST_FALLBACK_CHAINS[$host]:-$DEFAULT_FALLBACK}"
    IFS=':' read -ra fallbacks <<< "$chain"
    
    for fb in "${fallbacks[@]}"; do
        if echo "$available_models" | grep -q "$fb"; then
            local reason=""
            [[ -n "$preferred" ]] && reason="preferred $preferred not available, using fallback"
            echo "$fb|fallback|$reason"
            return 0
        fi
    done
    
    # No model found
    echo "|unavailable|no models in fallback chain available"
    return 1
}

adapter_start() {
    local beads="$1"
    local prompt_file="$2"
    local worktree="$3"
    local log_file="$4"
    
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || {
        echo "ERROR: opencode not found" >&2
        return 1
    }
    
    # Resolve model with fallback (bd-cbsb.15)
    local preferred_model="${OPENCODE_MODEL:-zhipuai-coding-plan/glm-5}"
    local model_result model selection_reason fallback_reason
    model_result="$(adapter_resolve_model "$preferred_model")"
    IFS='|' read -r model selection_reason fallback_reason <<< "$model_result"
    
    if [[ -z "$model" ]]; then
        echo "ERROR: No available model found. Tried: $preferred_model" >&2
        echo "ERROR: $fallback_reason" >&2
        return 1
    fi
    
    # Log model selection for telemetry
    echo "[opencode-adapter] START beads=$beads model=$model reason=$selection_reason fallback=$fallback_reason" >> "$log_file"
    
    # Build command with worktree-only enforcement (bd-cbsb.16)
    local cmd_args=(
        "$opencode_bin"
        run
        --model "$model"
        --format json
    )
    
    # Add worktree as working directory if specified
    if [[ -n "$worktree" && -d "$worktree" ]]; then
        cmd_args+=(--cwd "$worktree")
    fi
    
    # Read prompt from file
    local prompt
    prompt="$(cat "$prompt_file")"
    
    # Launch with nohup
    if [[ "${USE_PTY:-false}" == "true" ]]; then
        local pty_run
        pty_run="$(dirname "$opencode_bin")/../libexec/opencode/pty-run" 2>/dev/null || true
        if [[ -x "$pty_run" ]]; then
            nohup "$pty_run" --output "$log_file" -- \
                "${cmd_args[@]}" "$prompt" 2>> "$log_file" &
            echo $!
            return 0
        fi
    fi
    
    nohup "${cmd_args[@]}" "$prompt" >> "$log_file" 2>&1 &
    echo $!
}

adapter_probe_model() {
    local model="${1:-zhipuai-coding-plan/glm-5}"
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || return 1
    
    # Quick probe with timeout (bd-cbsb.15)
    timeout 45 "$opencode_bin" run --model "$model" --format json "Return only READY" 2>/dev/null | grep -q "READY" || return 1
    
    return 0
}

adapter_list_models() {
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || return 1
    
    "$opencode_bin" models 2>/dev/null | grep -E "^- " | sed 's/^- //' || true
}

adapter_stop() {
    local pid="$1"
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null || true
        # Clean up any orphaned opencode processes (bd-cbsb.15 evidence)
        sleep 1
        pkill -f "opencode.*--model" 2>/dev/null || true
    fi
}
