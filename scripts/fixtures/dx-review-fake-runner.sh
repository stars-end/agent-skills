#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true
state_dir="${DX_REVIEW_FAKE_STATE_DIR:-/tmp}"

arg_value() {
  local key="$1"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      "$key") echo "${2:-}"; return 0 ;;
    esac
    shift || true
  done
}

case "$cmd" in
  start)
    profile="$(arg_value --profile "$@")"
    beads="$(arg_value --beads "$@")"
    prompt_file="$(arg_value --prompt-file "$@")"
    echo "start:$beads:$profile:$(date +%s)" >> "$DX_REVIEW_FAKE_LOG"
    echo "prompt_file:$beads:$prompt_file" >> "$DX_REVIEW_FAKE_LOG"
    case "$profile" in
      claude-code-review)
        sleep "${DX_REVIEW_FAKE_CLAUDE_START_SEC:-3}"
        echo "started beads=$beads provider=claude-code"
        ;;
      cc-glm-review)
        if [[ "${DX_REVIEW_FAKE_CC_GLM_START_FAIL:-0}" == "1" ]]; then
          mkdir -p "$state_dir"
          printf '1\n' > "$state_dir/${beads}.start_failed"
          echo "reason_code=secret_auth_resolution_failed_after_preflight"
          echo "secret_ref_category=op-ref:default-Agent-Secrets-Production-ZAI_API_KEY"
          echo "preflight gate failed for provider cc-glm" >&2
          exit 22
        fi
        echo "started beads=$beads provider=cc-glm"
        ;;
      opencode-review)
        if [[ "${DX_REVIEW_FAKE_OPENCODE_START_FAIL:-0}" == "1" ]]; then
          mkdir -p "$state_dir"
          printf '1\n' > "$state_dir/${beads}.start_failed"
          echo "reason_code=opencode_mise_untrusted"
          echo "preflight gate failed for provider opencode" >&2
          exit 21
        fi
        echo "started beads=$beads provider=opencode"
        ;;
      *)
        echo "started beads=$beads provider=$profile"
        ;;
    esac
    ;;
  check)
    beads="$(arg_value --beads "$@")"
    echo "check:$beads:$(date +%s)" >> "$DX_REVIEW_FAKE_LOG"
    if [[ "${DX_REVIEW_FAKE_REPORT_MISSING:-0}" == "1" && "$beads" == *.glm ]]; then
      echo '{"beads":"'"$beads"'","state":"missing","reason_code":"no_meta"}'
      exit 1
    elif [[ -f "$state_dir/${beads}.start_failed" ]]; then
      if [[ "$beads" == *.glm ]]; then provider="cc-glm"; elif [[ "$beads" == *.opencode ]]; then provider="opencode"; else provider="unknown"; fi
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"start_failed","reason_code":"dx_runner_start_failed"}'
    elif [[ "${DX_REVIEW_FAKE_FORCE_START_FAILED:-0}" == "1" && "$beads" == *.glm ]]; then
      echo '{"beads":"'"$beads"'","provider":"cc-glm","state":"start_failed","reason_code":"dx_runner_start_failed"}'
    elif [[ "${DX_REVIEW_FAKE_RATE_LIMIT:-0}" == "1" && "$beads" == *.glm ]]; then
      echo '{"beads":"'"$beads"'","provider":"cc-glm","state":"exited_err","reason_code":"provider_rate_limited","mutation_count":1}'
    elif [[ "${DX_REVIEW_FAKE_GEMINI_STOPPED:-0}" == "1" && "$beads" == *.gemini ]]; then
      echo '{"beads":"'"$beads"'","provider":"gemini","state":"stopped","reason_code":"manual_stop","mutation_count":1}'
    elif [[ "$beads" == *.claude ]]; then
      echo '{"beads":"'"$beads"'","provider":"claude-code","state":"no_op_success","reason_code":"exit_zero_no_mutations"}'
    elif [[ "$beads" == *.glm ]]; then
      echo '{"beads":"'"$beads"'","provider":"cc-glm","state":"exited_ok","reason_code":"process_exit_with_rc"}'
    else
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"exited_ok","reason_code":"process_exit_with_rc"}'
    fi
    ;;
  report)
    beads="$(arg_value --beads "$@")"
    if [[ "${DX_REVIEW_FAKE_REPORT_MISSING:-0}" == "1" && "$beads" == *.glm ]]; then
      echo '{"beads":"'"$beads"'","state":"missing","reason_code":"no_meta"}'
      exit 1
    elif [[ "${DX_REVIEW_FAKE_GEMINI_STOPPED:-0}" == "1" && "$beads" == *.gemini ]]; then
      echo '{"beads":"'"$beads"'","provider":"gemini","state":"stopped","reason_code":"manual_stop","mutations":1}'
    elif [[ "${DX_REVIEW_FAKE_RATE_LIMIT:-0}" == "1" && "$beads" == *.glm ]]; then
      echo '{"beads":"'"$beads"'","provider":"cc-glm","state":"exited_err","reason_code":"provider_rate_limited","failure_class":"provider_rate_limited","failure_detail":"429 Rate limit reached","retryable":true,"provider_exit_code":1,"log_excerpt":"429 Rate limit reached","next_action":"retry_after_backoff_or_switch_fallback_reviewer","selected_model":"glm-5","mutations":1}'
    elif [[ "${DX_REVIEW_FAKE_EMPTY_SUCCESS:-0}" == "1" && "$beads" == *.glm ]]; then
      echo '{"beads":"'"$beads"'","provider":"cc-glm","state":"exited_ok","reason_code":"process_exit_with_rc"}'
    elif [[ "${DX_REVIEW_FAKE_REPORT_USAGE:-0}" == "1" ]]; then
      if [[ "$beads" == *.glm ]]; then provider="cc-glm"; elif [[ "$beads" == *.opencode ]]; then provider="opencode"; else provider="claude-code"; fi
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"exited_ok","reason_code":"process_exit_with_rc","verdict":"pass_with_findings","findings_count":2,"read_only_enforcement":"contract_only","input_tokens":101,"output_tokens":29,"total_tokens":130,"estimated_cost_usd":0.42}'
    elif [[ "$beads" == *.opencode ]]; then
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"exited_ok","reason_code":"process_exit_with_rc","verdict":"pass","findings_count":0,"read_only_enforcement":"contract_only"}'
    elif [[ "$beads" == *.glm ]]; then
      echo '{"beads":"'"$beads"'","provider":"cc-glm","state":"exited_ok","reason_code":"process_exit_with_rc","verdict":"pass_with_findings","findings_count":1,"read_only_enforcement":"contract_only"}'
    else
      echo '{"beads":"'"$beads"'","provider":"claude-code","state":"no_op_success","reason_code":"exit_zero_no_mutations","verdict":"approve_with_changes","findings_count":2,"read_only_enforcement":"contract_only"}'
    fi
    ;;
  preflight)
    echo "=== Preflight PASSED ==="
    ;;
  *)
    echo "unsupported fake dx-runner command: $cmd" >&2
    exit 2
    ;;
esac
