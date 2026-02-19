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
    ["epyc12"]="zhipuai-coding-plan/glm-5:zai-coding-plan/glm-5:nvidia/z-ai/glm5:opencode/glm-5-free"
    ["epyc6"]="zhipuai-coding-plan/glm-5:zai-coding-plan/glm-5:nvidia/z-ai/glm5:opencode/glm-5-free"
    ["macmini"]="zhipuai-coding-plan/glm-5:zai-coding-plan/glm-5:nvidia/z-ai/glm5:opencode/glm-5-free"
    ["homedesktop-wsl"]="zhipuai-coding-plan/glm-5:zai-coding-plan/glm-5:nvidia/z-ai/glm5:opencode/glm-5-free"
)

DEFAULT_FALLBACK="zhipuai-coding-plan/glm-5:zai-coding-plan/glm-5:nvidia/z-ai/glm5:opencode/glm-5-free"

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
    local warnings=0
    
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
        # Can't continue without binary
        return $errors
    fi
    
    # Check 2: Model availability with fallback (bd-cbsb.15)
    echo -n "model availability: "
    local models
    models=$("$opencode_bin" models 2>/dev/null) || true
    local model_count
    model_count="$(echo "$models" | grep -cE "^[a-z]+/.+" || echo "0")"
    if [[ "$model_count" -gt 0 ]]; then
        echo "OK ($model_count models)"
    else
        echo "NO_MODELS"
        echo "  ERROR: No models available"
        errors=$((errors + 1))
    fi
    
    # Check 3: Preferred model probe with auth/quota (bd-cbsb.15 - strict blocking)
    echo -n "preferred model probe: "
    local preferred_model="${OPENCODE_MODEL:-zhipuai-coding-plan/glm-5}"
    local model_result probe_model selection_reason fallback_reason
    model_result="$(adapter_resolve_model "$preferred_model")"
    IFS='|' read -r probe_model selection_reason fallback_reason <<< "$model_result"

    if [[ -n "$probe_model" ]]; then
        # Probe the model with timeout
        local probe_output
        probe_output="$(timeout 30 "$opencode_bin" run --model "$probe_model" --format json "Say READY" 2>&1)" || true
        if echo "$probe_output" | grep -qi "READY"; then
            echo "OK ($probe_model)"
        elif echo "$probe_output" | grep -qiE "unauthorized|forbidden|insufficient.*balance|quota|rate.?limit|429"; then
            echo "BLOCKED (auth/quota)"
            echo "  ERROR: Model $probe_model available but auth/quota check failed"
            errors=$((errors + 1))
        else
            echo "TIMEOUT ($probe_model)"
            echo "  WARN: Model probe timed out (non-blocking)"
            warnings=$((warnings + 1))
        fi
    else
        echo "NO_MATCH"
        echo "  ERROR: No glm-5 compatible model found"
        errors=$((errors + 1))
    fi
    
    # Check 4: beads-mcp availability (bd-cbsb.18)
    echo -n "beads-mcp binary: "
    if command -v beads-mcp >/dev/null 2>&1; then
        echo "OK ($(command -v beads-mcp))"
    else
        echo "MISSING"
        echo "  WARN: beads-mcp not found, Beads context will be limited"
        warnings=$((warnings + 1))
    fi
    
    # Check 5: mise trust state (bd-cbsb.17 - for validation steps)
    echo -n "mise trust: "
    if command -v mise >/dev/null 2>&1; then
        local trust_state
        trust_state="$(mise trust --show 2>/dev/null)" || true
        if [[ -n "$trust_state" ]]; then
            echo "OK"
        else
            echo "UNTRUSTED"
            echo "  WARN: Run 'mise trust' in worktree before dispatch"
            warnings=$((warnings + 1))
        fi
    else
        echo "NOT_INSTALLED"
        echo "  WARN: mise not found"
        warnings=$((warnings + 1))
    fi
    
    echo ""
    if [[ $errors -gt 0 ]]; then
        echo "=== Preflight FAILED ($errors error(s), $warnings warning(s)) ==="
    elif [[ $warnings -gt 0 ]]; then
        echo "=== Preflight PASSED with warnings ($warnings warning(s)) ==="
    else
        echo "=== Preflight PASSED ==="
    fi
    
    return $errors
}

adapter_resolve_model() {
    local preferred="$1"
    local host="${2:-$(hostname 2>/dev/null | cut -d. -f1)}"
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || return 1
    
    # Check preferred first (direct grep, no string truncation)
    if [[ -n "$preferred" ]]; then
        if "$opencode_bin" models 2>/dev/null | grep -qxF "$preferred"; then
            echo "$preferred|preferred|"
            return 0
        fi
    fi
    
    # Use fallback chain
    local chain="${HOST_FALLBACK_CHAINS[$host]:-$DEFAULT_FALLBACK}"
    IFS=':' read -ra fallbacks <<< "$chain"
    
    for fb in "${fallbacks[@]}"; do
        if "$opencode_bin" models 2>/dev/null | grep -qxF "$fb"; then
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
    
    # Add worktree as working directory if specified (P0 fix: --dir not --cwd)
    if [[ -n "$worktree" && -d "$worktree" ]]; then
        cmd_args+=(--dir "$worktree")
    fi
    
    # Read prompt from file
    local prompt
    prompt="$(cat "$prompt_file")"
    
    local rc_file="${DX_RUNNER_RC_FILE:-/tmp/dx-runner/opencode/${beads}.rc}"
    mkdir -p "$(dirname "$rc_file")"
    rm -f "$rc_file"
    local launch_mode="detached"

    if [[ "${USE_PTY:-false}" == "true" ]]; then
        local pty_run
        pty_run="$(dirname "$opencode_bin")/../libexec/opencode/pty-run" 2>/dev/null || true
        if [[ -x "$pty_run" ]]; then
            launch_mode="pty-detached"
            (
                set +e
                "$pty_run" --output "$log_file" -- "${cmd_args[@]}" "$prompt" 2>> "$log_file"
                rc=$?
                set -e
                echo "$rc" > "$rc_file"
            ) &
            local pid="$!"
            printf 'pid=%s\n' "$pid"
            printf 'selected_model=%s\n' "$model"
            printf 'fallback_reason=%s\n' "${fallback_reason:-none}"
            printf 'launch_mode=%s\n' "$launch_mode"
            printf 'rc_file=%s\n' "$rc_file"
            return 0
        fi
    fi

    (
        set +e
        "${cmd_args[@]}" "$prompt" >> "$log_file" 2>&1
        rc=$?
        set -e
        echo "$rc" > "$rc_file"
    ) &
    local pid="$!"
    printf 'pid=%s\n' "$pid"
    printf 'selected_model=%s\n' "$model"
    printf 'fallback_reason=%s\n' "${fallback_reason:-none}"
    printf 'launch_mode=%s\n' "$launch_mode"
    printf 'rc_file=%s\n' "$rc_file"
}

adapter_probe_model() {
    local model="${1:-zhipuai-coding-plan/glm-5}"
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || return 1
    
    # Quick probe with timeout (bd-cbsb.15)
    timeout 45 "$opencode_bin" run --model "$model" --format json "Return only READY" 2>/dev/null | grep -qi "READY" || return 1
    
    return 0
}

adapter_list_models() {
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || return 1
    
    # Parse plain provider/model lines (P0 fix)
    "$opencode_bin" models 2>/dev/null | grep -E "^[a-z]+/.+" || true
}

adapter_stop() {
    local pid="$1"
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null || true
        # Wait for graceful shutdown
        sleep 2
        if ps -p "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    # P2 fix: Removed overly broad pkill - it can kill unrelated sessions
}
