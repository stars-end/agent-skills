#!/usr/bin/env bash
# gemini adapter for dx-runner
#
# Implements the adapter contract for Google Gemini CLI
#
# P1 fixes (bd-dxrunner-reliability):
#   - Default model updated to gemini-3-flash-preview
#   - Yolo flag (-y) support with GEMINI_NO_YOLO opt-out
#   - Robust cwd handling via launcher script
#
# Required functions:
#   adapter_start        - Start a job
#   adapter_check        - Check health state  
#   adapter_stop         - Stop a job
#   adapter_preflight    - Provider-specific preflight
#   adapter_probe_model  - Test model availability
#   adapter_list_models  - List available models

GEMINI_CANONICAL_MODEL="gemini-3-flash-preview"

adapter_find_gemini() {
    for candidate in "gemini" "gemini-cli" "/usr/local/bin/gemini" "$HOME/.local/bin/gemini"; do
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
        echo "  Install: npm install -g @google/gemini-cli (or equivalent)"
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
    
    # Check 3: Yolo mode configuration
    echo -n "yolo mode: "
    if [[ "${GEMINI_NO_YOLO:-false}" == "true" ]]; then
        echo "DISABLED (GEMINI_NO_YOLO=true)"
    else
        echo "ENABLED (default)"
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
    
    local model="${GEMINI_MODEL:-$GEMINI_CANONICAL_MODEL}"
    local use_yolo="true"
    if [[ "${GEMINI_NO_YOLO:-false}" == "true" ]]; then
        use_yolo="false"
    fi
    
    echo "[gemini-adapter] START beads=$beads model=$model yolo=$use_yolo" >> "$log_file"
    
    local prompt
    prompt="$(cat "$prompt_file")"
    
    local cmd_args=("$gemini_bin")
    
    # Add yolo flag (-y) unless opted out
    if [[ "$use_yolo" == "true" ]]; then
        cmd_args+=(-y)
    fi
    
    # Add model flag if supported
    if "$gemini_bin" --help 2>/dev/null | grep -q -- "--model"; then
        cmd_args+=(--model "$model")
    fi
    
    local rc_file="${DX_RUNNER_RC_FILE:-/tmp/dx-runner/gemini/${beads}.rc}"
    mkdir -p "$(dirname "$rc_file")"
    rm -f "$rc_file"
    local launch_mode="detached-script"
    local launcher
    launcher="$(mktemp "/tmp/gemini-launcher-${beads}.XXXXXX.sh")"
    chmod +x "$launcher"

    local worktree_arg=""
    if [[ -n "$worktree" && -d "$worktree" ]]; then
        worktree_arg="cd $(printf '%q' "$worktree") && "
    fi

    local prompt_escaped
    printf -v prompt_escaped '%q' "$prompt"
    
    cat > "$launcher" <<EOF
#!/usr/bin/env bash
set +e
${worktree_arg}${cmd_args[@]@Q} $prompt_escaped >> $(printf '%q' "$log_file") 2>&1
rc=\$?
echo "\$rc" > $(printf '%q' "$rc_file")
rm -f $(printf '%q' "$launcher")
EOF
    if command -v setsid >/dev/null 2>&1; then
        launch_mode="${launch_mode}+setsid"
        setsid "$launcher" >/dev/null 2>&1 < /dev/null &
    else
        launch_mode="${launch_mode}+nohup"
        nohup "$launcher" >/dev/null 2>&1 < /dev/null &
    fi
    local pid="$!"
    printf 'pid=%s\n' "$pid"
    printf 'selected_model=%s\n' "$model"
    printf 'fallback_reason=%s\n' "none"
    printf 'launch_mode=%s\n' "$launch_mode"
    printf 'rc_file=%s\n' "$rc_file"
}

adapter_probe_model() {
    local model="${1:-$GEMINI_CANONICAL_MODEL}"
    local gemini_bin
    gemini_bin="$(adapter_find_gemini)" || return 1
    
    # Quick probe
    timeout 30 "$gemini_bin" -y --model "$model" "Return READY" 2>/dev/null | grep -q "READY" || return 1
    
    return 0
}

adapter_list_models() {
    echo "gemini-1.5-flash"
    echo "gemini-1.5-pro"
    echo "gemini-2.0-flash"
    echo "gemini-2.0-pro"
    echo "gemini-3-flash-preview"
    echo "gemini-3-pro-preview"
}

adapter_stop() {
    local pid="$1"
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        if ps -p "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
}
