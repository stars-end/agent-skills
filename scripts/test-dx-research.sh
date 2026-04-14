#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DX_RESEARCH="${SCRIPT_DIR}/dx-research"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAIL=$((FAIL + 1))
}

make_fake_runner() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true
state_dir="${DX_RESEARCH_FAKE_STATE_DIR:-/tmp}"

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
    echo "start:$beads:$profile:$(date +%s)" >> "$DX_RESEARCH_FAKE_LOG"
    echo "prompt_file:$beads:$prompt_file" >> "$DX_RESEARCH_FAKE_LOG"
    case "$profile" in
      gemini-research)
        if [[ "${DX_RESEARCH_FAKE_GEMINI_START_FAIL:-0}" == "1" ]]; then
          mkdir -p "$state_dir"
          printf '1\n' > "$state_dir/${beads}.start_failed"
          echo "reason_code=canonical_model_probe_timeout"
          echo "model probe timed out" >&2
          exit 31
        fi
        echo "started beads=$beads provider=gemini"
        ;;
      cc-glm-research)
        if [[ "${DX_RESEARCH_FAKE_CC_GLM_START_FAIL:-0}" == "1" ]]; then
          mkdir -p "$state_dir"
          printf '1\n' > "$state_dir/${beads}.start_failed"
          echo "reason_code=auth_missing"
          echo "preflight gate failed for provider cc-glm" >&2
          exit 32
        fi
        echo "started beads=$beads provider=cc-glm"
        ;;
      *)
        echo "started beads=$beads provider=$profile"
        ;;
    esac
    ;;
  check)
    beads="$(arg_value --beads "$@")"
    echo "check:$beads:$(date +%s)" >> "$DX_RESEARCH_FAKE_LOG"
    if [[ -f "$state_dir/${beads}.start_failed" ]]; then
      if [[ "$beads" == *.gemini ]]; then provider="gemini"; else provider="cc-glm"; fi
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"start_failed","reason_code":"dx_runner_start_failed"}'
    elif [[ "${DX_RESEARCH_FAKE_TIMEOUT_MODE:-0}" == "1" ]]; then
      if [[ "$beads" == *.gemini ]]; then provider="gemini"; else provider="cc-glm"; fi
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"running","reason_code":"still_running"}'
    elif [[ "${DX_RESEARCH_FAKE_REPORT_MISSING:-0}" == "1" ]]; then
      echo '{"beads":"'"$beads"'","state":"missing","reason_code":"no_meta"}'
      exit 1
    else
      if [[ "$beads" == *.gemini ]]; then provider="gemini"; else provider="cc-glm"; fi
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"exited_ok","reason_code":"process_exit_with_rc"}'
    fi
    ;;
  report)
    beads="$(arg_value --beads "$@")"
    if [[ "${DX_RESEARCH_FAKE_REPORT_MISSING:-0}" == "1" ]]; then
      echo '{"beads":"'"$beads"'","state":"missing","reason_code":"no_meta"}'
      exit 1
    fi
    if [[ "${DX_RESEARCH_FAKE_TIMEOUT_MODE:-0}" == "1" ]]; then
      if [[ "$beads" == *.gemini ]]; then provider="gemini"; else provider="cc-glm"; fi
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"running","reason_code":"still_running","mutations":0}'
      exit 0
    fi
    if [[ "${DX_RESEARCH_FAKE_REPORT_WITH_SOURCES:-0}" == "1" ]]; then
      if [[ "$beads" == *.gemini ]]; then provider="gemini"; else provider="cc-glm"; fi
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"exited_ok","reason_code":"process_exit_with_rc","mutations":0,"input_tokens":120,"output_tokens":30,"total_tokens":150,"estimated_cost_usd":0.12,"sources":[{"id":"s1","kind":"url","reference":"https://example.com","supports":["c1"]}],"claims":[{"id":"c1","claim":"A is faster than B","source_ids":["s1"],"inference":false}]}'
    else
      if [[ "$beads" == *.gemini ]]; then provider="gemini"; else provider="cc-glm"; fi
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"exited_ok","reason_code":"process_exit_with_rc","mutations":0}'
    fi
    ;;
  preflight)
    profile="$(arg_value --profile "$@")"
    echo "preflight:$profile" >> "$DX_RESEARCH_FAKE_LOG"
    if [[ "${DX_RESEARCH_FAKE_PREFLIGHT_FAIL:-0}" == "1" && "$profile" == "gemini-research" ]]; then
      echo "preflight failed: gemini unavailable" >&2
      exit 9
    fi
    echo "=== Preflight PASSED ==="
    ;;
  *)
    echo "unsupported fake dx-runner command: $cmd" >&2
    exit 2
    ;;
esac
EOF
    chmod +x "$path"
}

test_primary_gemini_success() {
    echo "=== Testing primary gemini success path ==="
    local tmp fake out rc summary
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_RESEARCH_FAKE_LOG="$tmp/fake.log"
    export DX_RESEARCH_FAKE_STATE_DIR="$tmp/state"
    unset DX_RESEARCH_FAKE_GEMINI_START_FAIL
    unset DX_RESEARCH_FAKE_CC_GLM_START_FAIL
    unset DX_RESEARCH_FAKE_TIMEOUT_MODE
    unset DX_RESEARCH_FAKE_REPORT_MISSING
    unset DX_RESEARCH_FAKE_REPORT_WITH_SOURCES

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" run --beads bd-rs1 --topic "compare lanes" --wait --timeout-sec 8 --poll-sec 1 2>&1)"
    rc=$?
    set -e

    summary="/tmp/dx-research/bd-rs1/summary.json"
    if [[ "$rc" -eq 0 && -f "$summary" ]]; then
        pass "run succeeds with primary gemini and writes summary"
    else
        fail "run failed unexpectedly: rc=$rc output=$out"
    fi

    if ! grep -q "start:bd-rs1.ccglm:cc-glm-research" "$DX_RESEARCH_FAKE_LOG"; then
        pass "fallback not launched on primary success"
    else
        fail "fallback launched despite primary success"
    fi

    rm -rf "$tmp"
}

test_primary_start_failure_fallback_success() {
    echo "=== Testing primary failure triggers fallback exactly once ==="
    local tmp fake out rc gemini_checks ccglm_starts summary
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_RESEARCH_FAKE_LOG="$tmp/fake.log"
    export DX_RESEARCH_FAKE_STATE_DIR="$tmp/state"
    export DX_RESEARCH_FAKE_GEMINI_START_FAIL=1
    unset DX_RESEARCH_FAKE_CC_GLM_START_FAIL
    unset DX_RESEARCH_FAKE_TIMEOUT_MODE
    unset DX_RESEARCH_FAKE_REPORT_MISSING
    unset DX_RESEARCH_FAKE_REPORT_WITH_SOURCES

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" run --beads bd-rs2 --topic "fallback test" --wait --timeout-sec 8 --poll-sec 1 2>&1)"
    rc=$?
    set -e

    gemini_checks="$(grep -c "check:bd-rs2.gemini" "$DX_RESEARCH_FAKE_LOG" || true)"
    ccglm_starts="$(grep -c "start:bd-rs2.ccglm:cc-glm-research" "$DX_RESEARCH_FAKE_LOG" || true)"
    summary="/tmp/dx-research/bd-rs2/summary.json"

    if [[ "$rc" -eq 0 && -f "$summary" ]]; then
        pass "fallback run succeeds and writes summary"
    else
        fail "fallback run failed: rc=$rc output=$out"
    fi
    if [[ "$ccglm_starts" -eq 1 ]]; then
        pass "fallback launches exactly once"
    else
        fail "unexpected fallback start count: $ccglm_starts"
    fi
    if [[ "$gemini_checks" -le 1 ]]; then
        pass "failed primary is not repeatedly polled (at most one summarize probe)"
    else
        fail "failed primary was polled repeatedly: count=$gemini_checks"
    fi
    if echo "$out" | grep -q "fallback: attempted=true used=true"; then
        pass "fallback visibility is present in run output"
    else
        fail "fallback visibility missing in run output: $out"
    fi

    rm -rf "$tmp"
}

test_no_meta_reason_replaced_by_start_log_root_cause() {
    echo "=== Testing no_meta reason replacement from start log ==="
    local tmp fake run_dir out rc summary
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_RESEARCH_FAKE_LOG="$tmp/fake.log"
    export DX_RESEARCH_FAKE_STATE_DIR="$tmp/state"
    export DX_RESEARCH_FAKE_REPORT_MISSING=1
    unset DX_RESEARCH_FAKE_REPORT_WITH_SOURCES
    unset DX_RESEARCH_FAKE_GEMINI_START_FAIL

    run_dir="/tmp/dx-research/bd-rs3"
    rm -rf "$run_dir"
    mkdir -p "$run_dir"
    printf 'reason_code=canonical_model_probe_timeout\nmodel probe timed out\n' > "$run_dir/bd-rs3.gemini.start.log"

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" summarize --beads bd-rs3 2>&1)"
    rc=$?
    set -e
    summary="$run_dir/summary.json"

    if [[ "$rc" -ne 0 && -f "$summary" && "$(cat "$summary")" == *canonical_model_probe_timeout* && "$(cat "$summary")" != *'"reason_code":"no_meta"'* ]]; then
        pass "summarize preserves start-log root cause over no_meta"
    else
        fail "start-log root cause was not preserved: rc=$rc output=$out"
    fi

    rm -rf "$tmp"
}

test_prompt_content_flags() {
    echo "=== Testing prompt content flags ==="
    local tmp fake prompt_path out rc
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_RESEARCH_FAKE_LOG="$tmp/fake.log"
    export DX_RESEARCH_FAKE_STATE_DIR="$tmp/state"
    unset DX_RESEARCH_FAKE_GEMINI_START_FAIL
    unset DX_RESEARCH_FAKE_REPORT_MISSING
    unset DX_RESEARCH_FAKE_REPORT_WITH_SOURCES

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" run --beads bd-rs4 --topic "flags" --depth quick --no-web --local-only --wait --timeout-sec 8 --poll-sec 1 2>&1)"
    rc=$?
    set -e
    prompt_path="/tmp/dx-research/bd-rs4/research.prompt"

    if [[ "$rc" -eq 0 && -f "$prompt_path" ]]; then
        pass "run writes prompt file"
    else
        fail "prompt file missing: rc=$rc output=$out"
    fi

    if grep -q 'Depth: `quick`' "$prompt_path" \
        && grep -q 'Web mode: `no-web`' "$prompt_path" \
        && grep -q 'Local-only: `true`' "$prompt_path" \
        && grep -q 'Quick mode: produce a bounded decision memo' "$prompt_path" \
        && grep -q 'External web research is forbidden' "$prompt_path" \
        && grep -q 'Use only repository/local evidence' "$prompt_path"; then
        pass "prompt captures depth/no-web/local-only contract"
    else
        fail "prompt missing expected depth/no-web/local-only contract"
    fi

    rm -rf "$tmp"
}

test_summarize_artifact_creation_and_source_grounding() {
    echo "=== Testing summarize artifacts and source grounding fields ==="
    local tmp fake out rc run_dir
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_RESEARCH_FAKE_LOG="$tmp/fake.log"
    export DX_RESEARCH_FAKE_STATE_DIR="$tmp/state"
    export DX_RESEARCH_FAKE_REPORT_WITH_SOURCES=1
    unset DX_RESEARCH_FAKE_REPORT_MISSING
    unset DX_RESEARCH_FAKE_GEMINI_START_FAIL

    run_dir="/tmp/dx-research/bd-rs5"
    rm -rf "$run_dir"
    mkdir -p "$run_dir"
    printf 'started beads=bd-rs5.gemini provider=gemini\n' > "$run_dir/bd-rs5.gemini.start.log"

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" summarize --beads bd-rs5 2>&1)"
    rc=$?
    set -e

    if [[ "$rc" -eq 0 && -f "$run_dir/summary.json" && -f "$run_dir/summary.md" && -f "$run_dir/sources.json" && -f "$run_dir/claims.json" ]]; then
        pass "summarize writes summary/sources/claims artifacts"
    else
        fail "summarize artifacts missing: rc=$rc output=$out"
    fi

    if grep -q '"source_grounding":"available"' "$run_dir/summary.json"; then
        pass "summary marks source grounding available when structured data exists"
    else
        fail "source grounding was not marked available"
    fi

    if grep -q '"mutations":0' "$run_dir/summary.json" && grep -q 'mutations=0' "$run_dir/summary.md"; then
        pass "summary surfaces mutation count from provider report"
    else
        fail "summary did not surface mutation count"
    fi

    if grep -q '^## Answer' "$run_dir/summary.md" \
        && grep -q '^## Evidence' "$run_dir/summary.md" \
        && grep -q '^## Contradictions' "$run_dir/summary.md" \
        && grep -q '^## Confidence' "$run_dir/summary.md" \
        && grep -q '^## Decision Impact' "$run_dir/summary.md" \
        && grep -q '^## Open Questions' "$run_dir/summary.md" \
        && grep -q '^## Next Action' "$run_dir/summary.md"; then
        pass "summary.md includes required decision memo sections"
    else
        fail "summary.md missing required decision memo sections"
    fi

    rm -rf "$tmp"
}

test_summarize_extracts_labeled_json_from_log() {
    echo "=== Testing summarize extracts SOURCES_JSON/CLAIMS_JSON from provider log ==="
    local tmp fake out rc run_dir log_dir log_path
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_RESEARCH_FAKE_LOG="$tmp/fake.log"
    export DX_RESEARCH_FAKE_STATE_DIR="$tmp/state"
    unset DX_RESEARCH_FAKE_REPORT_WITH_SOURCES
    unset DX_RESEARCH_FAKE_REPORT_MISSING
    unset DX_RESEARCH_FAKE_GEMINI_START_FAIL

    run_dir="/tmp/dx-research/bd-rs7"
    log_dir="/tmp/dx-runner/gemini"
    log_path="$log_dir/bd-rs7.gemini.log"
    rm -rf "$run_dir"
    mkdir -p "$run_dir" "$log_dir"
    printf 'started beads=bd-rs7.gemini provider=gemini\n' > "$run_dir/bd-rs7.gemini.start.log"
    {
        printf 'Answer: local docs are sufficient.\n'
        printf 'SOURCES_JSON=[{"id":"slog1","kind":"file","reference":"extended/dx-research/SKILL.md","supports":["clog1"]}]\n'
        printf 'CLAIMS_JSON=[{"id":"clog1","claim":"dx-research has a skill contract","source_ids":["slog1"],"inference":false}]\n'
    } > "$log_path"

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" summarize --beads bd-rs7 2>&1)"
    rc=$?
    set -e

    if [[ "$rc" -eq 0 ]] && grep -q '"source_grounding":"available"' "$run_dir/summary.json" \
        && grep -q 'slog1' "$run_dir/sources.json" \
        && grep -q 'clog1' "$run_dir/claims.json"; then
        pass "summarize extracts labeled structured output from provider log"
    else
        fail "labeled log extraction failed: rc=$rc output=$out"
    fi

    rm -rf "$tmp"
}

test_timeout_behavior() {
    echo "=== Testing timeout behavior ==="
    local tmp fake out rc run_dir
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_RESEARCH_FAKE_LOG="$tmp/fake.log"
    export DX_RESEARCH_FAKE_STATE_DIR="$tmp/state"
    export DX_RESEARCH_FAKE_TIMEOUT_MODE=1
    unset DX_RESEARCH_FAKE_REPORT_MISSING
    unset DX_RESEARCH_FAKE_REPORT_WITH_SOURCES
    unset DX_RESEARCH_FAKE_GEMINI_START_FAIL

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" run --beads bd-rs6 --topic "timeout" --wait --timeout-sec 2 --poll-sec 1 2>&1)"
    rc=$?
    set -e
    run_dir="/tmp/dx-research/bd-rs6"

    if [[ "$rc" -eq 124 ]] && echo "$out" | grep -q "timed out"; then
        pass "run exits 124 on timeout with timeout message"
    else
        fail "timeout behavior incorrect: rc=$rc output=$out"
    fi

    if [[ -f "$run_dir/summary.json" && -f "$run_dir/summary.md" ]] \
        && grep -q '"status":"not_reached"' "$run_dir/summary.json" \
        && grep -q "Research did not complete" "$run_dir/summary.md"; then
        pass "timeout still writes partial summary artifacts"
    else
        fail "timeout did not write useful partial summary artifacts"
    fi

    rm -rf "$tmp"
}

test_doctor_default_and_with_fallback() {
    echo "=== Testing doctor default profile selection ==="
    local tmp fake out rc
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_RESEARCH_FAKE_LOG="$tmp/fake.log"
    unset DX_RESEARCH_FAKE_PREFLIGHT_FAIL

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" doctor 2>&1)"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "doctor profile=gemini-research" && ! echo "$out" | grep -q "cc-glm-research"; then
        pass "doctor checks gemini-research by default"
    else
        fail "doctor default behavior incorrect: rc=$rc output=$out"
    fi

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_RESEARCH" doctor --with-fallback 2>&1)"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "doctor profile=gemini-research" && echo "$out" | grep -q "doctor profile=cc-glm-research"; then
        pass "doctor --with-fallback checks both profiles"
    else
        fail "doctor with fallback behavior incorrect: rc=$rc output=$out"
    fi

    rm -rf "$tmp"
}

main() {
    test_primary_gemini_success
    test_primary_start_failure_fallback_success
    test_no_meta_reason_replaced_by_start_log_root_cause
    test_prompt_content_flags
    test_summarize_artifact_creation_and_source_grounding
    test_summarize_extracts_labeled_json_from_log
    test_timeout_behavior
    test_doctor_default_and_with_fallback

    echo
    echo "Passed: $PASS"
    echo "Failed: $FAIL"

    if [[ "$FAIL" -ne 0 ]]; then
        exit 1
    fi
}

main "$@"
