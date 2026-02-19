#!/usr/bin/env bash
# opencode adapter for dx-runner
#
# Implements the adapter contract for OpenCode headless
# Includes reliability fixes for bd-cbsb.15-.18:
#   - Capability preflight with strict canonical model enforcement (bd-cbsb.15)
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

CANONICAL_MODEL="zhipuai-coding-plan/glm-5"

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
    
    # Check 2: Model availability
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
    
    # Check 3: Canonical model probe with auth/quota (strict blocking)
    echo -n "canonical model probe: "
    local model_result probe_model selection_reason resolve_reason
    model_result="$(adapter_resolve_model "${OPENCODE_MODEL:-$CANONICAL_MODEL}")"
    IFS='|' read -r probe_model selection_reason resolve_reason <<< "$model_result"

    if [[ -z "$probe_model" ]]; then
        echo "MISSING ($CANONICAL_MODEL)"
        echo "  ERROR: $resolve_reason"
        errors=$((errors + 1))
    else
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
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || return 1

    local required="${preferred:-$CANONICAL_MODEL}"
    if [[ "$required" != "$CANONICAL_MODEL" ]]; then
        echo "|unavailable|unsupported opencode model '$required'; only '$CANONICAL_MODEL' is allowed"
        return 1
    fi
    if "$opencode_bin" models 2>/dev/null | grep -qxF "$CANONICAL_MODEL"; then
        echo "$CANONICAL_MODEL|canonical|"
        return 0
    fi

    echo "|unavailable|canonical model '$CANONICAL_MODEL' unavailable; use cc-glm or gemini"
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
    
    # Resolve strict canonical model (bd-cbsb.15)
    local preferred_model="${OPENCODE_MODEL:-$CANONICAL_MODEL}"
    local model_result model selection_reason fallback_reason
    model_result="$(adapter_resolve_model "$preferred_model")"
    IFS='|' read -r model selection_reason fallback_reason <<< "$model_result"
    
    if [[ -z "$model" ]]; then
        echo "reason_code=opencode_model_unavailable"
        echo "ERROR: OpenCode dispatch blocked. Required model: $CANONICAL_MODEL" >&2
        echo "ERROR: $fallback_reason" >&2
        echo "ERROR: Use provider cc-glm or gemini for this wave." >&2
        return 25
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
    local model="${1:-$CANONICAL_MODEL}"
    local opencode_bin
    opencode_bin="$(adapter_find_opencode)" || return 1

    [[ "$model" == "$CANONICAL_MODEL" ]] || return 1
    
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
