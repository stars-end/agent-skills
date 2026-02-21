#!/usr/bin/env bash
# cc-glm adapter for dx-runner
#
# Implements the adapter contract for Claude via Z.ai
#
# Required functions:
#   adapter_start        - Start a job
#   adapter_check        - Check health state  
#   adapter_stop         - Stop a job
#   adapter_preflight    - Provider-specific preflight
#   adapter_probe_model  - Test model availability
#   adapter_list_models  - List available models
#   adapter_resolve_model - Resolve model with fallback (parity)
#   adapter_find_cc_glm  - Find Claude binary (parity)
#
# Exit codes (parity with opencode):
#   25 - Model unavailable

CC_GLM_CANONICAL_MODEL="glm-5"
ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_GLM_SCRIPTS="${ADAPTER_DIR}/../../extended/cc-glm/scripts"

adapter_find_cc_glm() {
    for candidate in "claude" "/home/linuxbrew/.linuxbrew/bin/claude" "/opt/homebrew/bin/claude" "$HOME/.local/bin/claude"; do
        if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

adapter_resolve_model() {
    local preferred="$1"
    local available_models
    available_models=("glm-4" "glm-5" "claude-3-5-sonnet-20241022")
    
    local required="${preferred:-$CC_GLM_CANONICAL_MODEL}"
    
    for m in "${available_models[@]}"; do
        if [[ "$m" == "$required" ]]; then
            echo "$required|available|"
            return 0
        fi
    done
    
    local fallback="$CC_GLM_CANONICAL_MODEL"
    echo "$fallback|fallback|preferred model '$required' not available, using canonical"
    return 0
}

adapter_preflight() {
    local errors=0
    
    # Check 1: Claude binary
    echo -n "claude binary: "
    if command -v claude >/dev/null 2>&1; then
        echo "OK ($(command -v claude))"
    else
        echo "MISSING"
        echo "  ERROR: claude CLI not found"
        errors=$((errors + 1))
    fi
    
    # Check 2: Auth resolution
    echo -n "auth resolution: "
    local auth_ok=false
    local auth_source=""
    
    if [[ -n "${CC_GLM_AUTH_TOKEN:-}" ]]; then
        auth_ok=true
        auth_source="CC_GLM_AUTH_TOKEN"
    elif [[ -n "${CC_GLM_TOKEN_FILE:-}" ]]; then
        if [[ -f "${CC_GLM_TOKEN_FILE}" ]]; then
            auth_ok=true
            auth_source="CC_GLM_TOKEN_FILE"
        else
            echo "TOKEN_FILE_MISSING"
            echo "  ERROR: CC_GLM_TOKEN_FILE=${CC_GLM_TOKEN_FILE} not found"
            errors=$((errors + 1))
        fi
    elif [[ -n "${ZAI_API_KEY:-}" ]]; then
        if [[ "$ZAI_API_KEY" == op://* ]]; then
            if command -v op >/dev/null 2>&1; then
                auth_source="ZAI_API_KEY (op://)"
                # P1 fix: Add 30s timeout to op read to prevent hanging on macmini (bd-5wys.26)
                if timeout 30 op read "$ZAI_API_KEY" >/dev/null 2>&1; then
                    auth_ok=true
                else
                    echo "AUTH_PROBE_TIMEOUT"
                    echo "  ERROR: op read timed out or failed for ZAI_API_KEY"
                    errors=$((errors + 1))
                fi
            else
                echo "OP_CLI_MISSING"
                echo "  ERROR: ZAI_API_KEY is op:// reference but op CLI not found"
                errors=$((errors + 1))
            fi
        else
            auth_ok=true
            auth_source="ZAI_API_KEY"
        fi
    else
        # Try default op:// path
        if command -v op >/dev/null 2>&1; then
            auth_source="default op://"
            # P1 fix: Add 30s timeout to op read to prevent hanging on macmini (bd-5wys.26)
            if timeout 30 op read "op://${CC_GLM_OP_VAULT:-dev}/Agent-Secrets-Production/ZAI_API_KEY" >/dev/null 2>&1; then
                auth_ok=true
            else
                echo "AUTH_PROBE_TIMEOUT"
                echo "  ERROR: No auth source configured and default op:// resolution timed out or failed"
                errors=$((errors + 1))
            fi
        else
            echo "NO_AUTH_SOURCE"
            echo "  ERROR: No auth source configured"
            errors=$((errors + 1))
        fi
    fi
    
    if [[ "$auth_ok" == "true" ]]; then
        echo "OK ($auth_source)"
    fi
    
    # Check 3: Model config
    echo -n "model config: "
    local model="${CC_GLM_MODEL:-glm-5}"
    echo "OK ($model)"
    
    # Check 4: Base URL
    echo -n "backend URL: "
    local base_url="${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}"
    echo "$base_url"
    
    return $errors
}

adapter_start() {
    local beads="$1"
    local prompt_file="$2"
    local worktree="$3"
    local log_file="$4"
    
    local headless="${CC_GLM_SCRIPTS}/cc-glm-headless.sh"
    local pty_run="${CC_GLM_SCRIPTS}/pty-run.sh"
    
    if [[ ! -x "$headless" ]]; then
        echo "ERROR: cc-glm-headless.sh not found at $headless" >&2
        return 1
    fi
    
    # Build environment for headless run
    local model="${CC_GLM_MODEL:-glm-5}"
    local base_url="${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}"
    
    # Write startup heartbeat
    echo "[cc-glm-adapter] START beads=$beads model=$model" >> "$log_file"
    
    local rc_file="${DX_RUNNER_RC_FILE:-/tmp/dx-runner/cc-glm/${beads}.rc}"
    mkdir -p "$(dirname "$rc_file")"
    rm -f "$rc_file"
    local launch_mode="detached-script"
    local launcher
    launcher="$(mktemp "/tmp/ccglm-launcher-${beads}.XXXXXX.sh")"
    chmod +x "$launcher"

    local run_q=""
    if [[ "${USE_PTY:-false}" == "true" && -x "$pty_run" ]]; then
        launch_mode="pty-detached-script"
        printf -v run_q '%q ' "$pty_run" --output "$log_file" -- env CC_GLM_MODEL="$model" CC_GLM_BASE_URL="$base_url" "$headless" --prompt-file "$prompt_file"
        run_q="${run_q% }"
    else
        printf -v run_q '%q ' env CC_GLM_MODEL="$model" CC_GLM_BASE_URL="$base_url" "$headless" --prompt-file "$prompt_file"
        run_q="${run_q% }"
    fi

    cat > "$launcher" <<EOF
#!/usr/bin/env bash
set +e
$run_q >> $(printf '%q' "$log_file") 2>&1
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
    printf 'execution_mode=%s\n' "$launch_mode"
    printf 'rc_file=%s\n' "$rc_file"
}

adapter_probe_model() {
    local model="${1:-${CC_GLM_MODEL:-glm-5}}"
    local base_url="${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}"
    
    # Resolve auth
    local auth_token=""
    if [[ -n "${CC_GLM_AUTH_TOKEN:-}" ]]; then
        auth_token="$CC_GLM_AUTH_TOKEN"
    elif [[ -n "${ZAI_API_KEY:-}" ]]; then
        if [[ "$ZAI_API_KEY" == op://* ]]; then
            # P1 fix: Add 30s timeout to op read (bd-5wys.26)
            auth_token="$(timeout 30 op read "$ZAI_API_KEY" 2>/dev/null)" || return 1
        else
            auth_token="$ZAI_API_KEY"
        fi
    else
        # P1 fix: Add 30s timeout to op read (bd-5wys.26)
        auth_token="$(timeout 30 op read "op://${CC_GLM_OP_VAULT:-dev}/Agent-Secrets-Production/ZAI_API_KEY" 2>/dev/null)" || return 1
    fi
    
    # Quick probe with timeout
    timeout 15 curl -s -X POST \
        -H "x-api-key: $auth_token" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "{\"model\":\"$model\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}]}" \
        "$base_url/messages" | grep -q '"type":"message"' || return 1
    
    return 0
}

adapter_list_models() {
    # cc-glm uses Z.ai models
    echo "glm-4"
    echo "glm-5"
    echo "claude-3-5-sonnet-20241022"
}

adapter_stop() {
    local pid="$1"
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null || true
        sleep 2
        if ps -p "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
}
