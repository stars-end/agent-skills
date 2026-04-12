#!/usr/bin/env bash
# claude-code adapter for dx-runner
#
# Implements native Claude Code CLI headless execution.
# This is distinct from cc-glm, which is the Z.ai/GLM wrapper lane.
#
# Required functions:
#   adapter_start
#   adapter_preflight
#   adapter_probe_model
#   adapter_list_models
#   adapter_resolve_model
#   adapter_stop

CLAUDE_CODE_CANONICAL_MODEL="${CLAUDE_CODE_CANONICAL_MODEL:-opus}"
CLAUDE_CODE_PERMISSION_MODE="${CLAUDE_CODE_PERMISSION_MODE:-dontAsk}"
CLAUDE_CODE_MAX_BUDGET_USD="${CLAUDE_CODE_MAX_BUDGET_USD:-2}"

adapter_find_claude_code() {
    for candidate in "claude" "/opt/homebrew/bin/claude" "/usr/local/bin/claude" "/home/linuxbrew/.linuxbrew/bin/claude" "$HOME/.local/bin/claude"; do
        if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

adapter_list_models() {
    echo "opus"
    echo "sonnet"
}

adapter_resolve_model() {
    local preferred="${1:-$CLAUDE_CODE_CANONICAL_MODEL}"
    case "$preferred" in
        opus|sonnet|claude-*)
            echo "$preferred|available|"
            return 0
            ;;
        *)
            echo "|unavailable|unsupported claude-code model '$preferred'; canonical='$CLAUDE_CODE_CANONICAL_MODEL'"
            return 1
            ;;
    esac
}

adapter_preflight() {
    local errors=0
    local claude_bin

    echo -n "claude binary: "
    claude_bin="$(adapter_find_claude_code || true)"
    if [[ -n "$claude_bin" ]]; then
        echo "OK ($claude_bin)"
    else
        echo "MISSING"
        echo "  ERROR_CODE=claude_code_binary_missing severity=error action=install_claude_code_cli"
        echo "  ERROR: claude CLI not found"
        echo "  Install: npm install -g @anthropic-ai/claude-code"
        return 1
    fi

    echo -n "headless cli flags: "
    local help_text
    help_text="$("$claude_bin" --help 2>/dev/null || true)"
    if printf '%s\n' "$help_text" | grep -q -- "--print" \
        && printf '%s\n' "$help_text" | grep -q -- "--model" \
        && printf '%s\n' "$help_text" | grep -q -- "--output-format" \
        && printf '%s\n' "$help_text" | grep -q -- "--max-budget-usd"; then
        echo "OK"
    else
        echo "MISSING"
        echo "  ERROR_CODE=claude_code_headless_flags_missing severity=error action=upgrade_claude_code_cli"
        echo "  ERROR: claude CLI does not expose required headless flags"
        errors=$((errors + 1))
    fi

    echo -n "canonical model probe: "
    if adapter_probe_model "${CLAUDE_CODE_MODEL:-$CLAUDE_CODE_CANONICAL_MODEL}" >/dev/null 2>&1; then
        echo "OK (${CLAUDE_CODE_MODEL:-$CLAUDE_CODE_CANONICAL_MODEL})"
    else
        echo "FAILED"
        echo "  ERROR_CODE=claude_code_auth_or_model_unavailable severity=error action=check_claude_auth_or_model"
        errors=$((errors + 1))
    fi

    return "$errors"
}

adapter_start() {
    local beads="$1"
    local prompt_file="$2"
    local worktree="$3"
    local log_file="$4"

    local claude_bin
    claude_bin="$(adapter_find_claude_code)" || {
        echo "ERROR: claude not found" >&2
        return 1
    }

    local model_result model selection_reason fallback_reason
    model_result="$(adapter_resolve_model "${CLAUDE_CODE_MODEL:-$CLAUDE_CODE_CANONICAL_MODEL}")" || true
    IFS='|' read -r model selection_reason fallback_reason <<< "$model_result"
    if [[ -z "$model" ]]; then
        echo "reason_code=claude_code_model_unavailable"
        echo "ERROR: $fallback_reason" >&2
        return 25
    fi

    if [[ -z "$worktree" || ! -d "$worktree" ]]; then
        echo "reason_code=worktree_missing_for_claude_code"
        echo "ERROR: worktree must be an existing directory for claude-code dispatch." >&2
        return 22
    fi

    local prompt
    prompt="$(cat "$prompt_file")"

    local rc_file="${DX_RUNNER_RC_FILE:-/tmp/dx-runner/claude-code/${beads}.rc}"
    mkdir -p "$(dirname "$rc_file")"
    rm -f "$rc_file"

    echo "[claude-code-adapter] START beads=$beads model=$model permission_mode=$CLAUDE_CODE_PERMISSION_MODE" >> "$log_file"

    local cmd_args=(
        "$claude_bin"
        --print
        --model "$model"
        --output-format text
        --no-session-persistence
        --max-budget-usd "$CLAUDE_CODE_MAX_BUDGET_USD"
        --permission-mode "$CLAUDE_CODE_PERMISSION_MODE"
    )

    if [[ -n "${CLAUDE_CODE_EXTRA_ARGS:-}" ]]; then
        # shellcheck disable=SC2206
        local extra_args=( $CLAUDE_CODE_EXTRA_ARGS )
        cmd_args+=("${extra_args[@]}")
    fi

    local launcher
    launcher="$(mktemp "/tmp/dx-runner/claude-code-launcher-${beads}.XXXXXX")"
    chmod +x "$launcher"

    cat > "$launcher" <<EOF
#!/usr/bin/env bash
set +e
cd $(printf '%q' "$worktree") && ${cmd_args[@]@Q} $(printf '%q' "$prompt") >> $(printf '%q' "$log_file") 2>&1
rc=\$?
echo "\$rc" > $(printf '%q' "$rc_file")
rm -f $(printf '%q' "$launcher")
EOF

    local launch_mode="detached-script"
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
    printf 'fallback_reason=%s\n' "${fallback_reason:-none}"
    printf 'launch_mode=%s\n' "$launch_mode"
    printf 'execution_mode=%s\n' "$launch_mode"
    printf 'rc_file=%s\n' "$rc_file"
}

adapter_probe_model() {
    local model="${1:-$CLAUDE_CODE_CANONICAL_MODEL}"
    local claude_bin
    claude_bin="$(adapter_find_claude_code)" || return 1

    "$claude_bin" --print \
        --model "$model" \
        --output-format text \
        --no-session-persistence \
        --max-budget-usd "${CLAUDE_CODE_PROBE_MAX_BUDGET_USD:-0.50}" \
        --permission-mode "$CLAUDE_CODE_PERMISSION_MODE" \
        "Return exactly READY." 2>/dev/null | grep -q "READY"
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
