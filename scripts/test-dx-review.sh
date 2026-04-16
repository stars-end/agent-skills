#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DX_REVIEW="${SCRIPT_DIR}/dx-review"

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
    cp "$SCRIPT_DIR/fixtures/dx-review-fake-runner.sh" "$path"
    chmod +x "$path"
}

make_fake_gh() {
    local path="$1"
    cp "$SCRIPT_DIR/fixtures/dx-review-fake-gh.sh" "$path"
    chmod +x "$path"
}

test_parallel_start_and_glm_fallback() {
    echo "=== Testing dx-review parallel start + GLM fallback handling ==="

    local tmp fake worktree out rc claude_ts glm_ts opencode_ts diff_sec
    local summary_json summary_md
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    worktree="$tmp/worktree"
    mkdir -p "$worktree"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    export DX_REVIEW_FAKE_CLAUDE_START_SEC=3
    export DX_REVIEW_FAKE_CC_GLM_START_FAIL=1
    unset DX_REVIEW_FAKE_OPENCODE_START_FAIL

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" run --beads bd-test --worktree "$worktree" --prompt "review only" --wait --timeout-sec 8 --poll-sec 1 2>&1)"
    rc=$?
    set -e

    claude_ts="$(awk -F: '$3=="claude-code-review"{print $4; exit}' "$DX_REVIEW_FAKE_LOG")"
    glm_ts="$(awk -F: '$3=="cc-glm-review"{print $4; exit}' "$DX_REVIEW_FAKE_LOG")"
    opencode_ts="$(awk -F: '$3=="opencode-review"{print $4; exit}' "$DX_REVIEW_FAKE_LOG")"
    diff_sec=$((claude_ts - glm_ts))
    if [[ "$diff_sec" -lt 0 ]]; then diff_sec=$((0 - diff_sec)); fi
    if [[ "$diff_sec" -lt 2 ]]; then
        pass "primary reviewers are started in parallel"
    else
        fail "primary reviewers appear serial (claude/glm start delta ${diff_sec}s)"
    fi

    if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "glm_primary_start_failed" && [[ -n "$opencode_ts" ]]; then
        pass "cc-glm start failure launches OpenCode fallback and preserves successful logical quorum"
    else
        fail "cc-glm fallback behavior incorrect: rc=$rc output=$out"
    fi

    if echo "$out" | grep -q "secret_auth_resolution_failed_after_preflight"; then
        pass "cc-glm auth start failure preserves specific secret resolution reason"
    else
        fail "cc-glm auth start failure did not preserve specific reason: $out"
    fi

    local glm_checks
    glm_checks="$(grep -c "check:bd-test.glm" "$DX_REVIEW_FAKE_LOG" || true)"
    if [[ "$glm_checks" -le 1 ]]; then
        pass "start-failed cc-glm primary is not polled during wait loop (only summarize probes once)"
    else
        fail "start-failed cc-glm primary was polled repeatedly: count=$glm_checks"
    fi

    if echo "$out" | grep -q "state=review_completed raw_state=no_op_success"; then
        pass "review no-op success is summarized as review_completed"
    else
        fail "review no-op success was not summarized clearly: $out"
    fi

    summary_json="/tmp/dx-review/bd-test/summary.json"
    summary_md="/tmp/dx-review/bd-test/summary.md"
    if [[ -f "$summary_json" && -f "$summary_md" ]]; then
        pass "run --wait writes summary artifacts"
    else
        fail "run --wait did not write summary artifacts"
    fi

    if echo "$out" | grep -q "effective quorum: 2/2 completed, 0 failed" \
        && echo "$out" | grep -q "provider outcomes: 2 completed, 0 failed, 1 not reached" \
        && echo "$out" | grep -q "summary.json:"; then
        pass "run --wait prints effective quorum, provider outcomes, and summary artifact paths"
    else
        fail "run --wait missing quorum/summary output: $out"
    fi

    rm -rf "$tmp"
}

test_summarize_default_reviewers_and_usage_unavailable() {
    echo "=== Testing dx-review summarize default reviewers + usage unavailable ==="

    local tmp fake out rc summary_json summary_md
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_OPENCODE_START_FAIL
    unset DX_REVIEW_FAKE_REPORT_USAGE

    rm -rf /tmp/dx-review/bd-sum
    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-sum 2>&1)"
    rc=$?
    set -e

    summary_json="/tmp/dx-review/bd-sum/summary.json"
    summary_md="/tmp/dx-review/bd-sum/summary.md"
    if [[ "$rc" -eq 0 && -f "$summary_json" && -f "$summary_md" ]]; then
        pass "summarize writes summary.json and summary.md"
    else
        fail "summarize did not write expected artifacts: rc=$rc output=$out"
    fi

    if grep -q '"usage":{"available":false' "$summary_json"; then
        pass "summary JSON marks usage unavailable when token/cost data missing"
    else
        fail "summary JSON missing usage unavailable contract"
    fi

    if grep -q '"input_tokens":null' "$summary_json" && grep -q '"output_tokens":null' "$summary_json" && grep -q '"estimated_cost_usd":null' "$summary_json" && grep -q '"source":null' "$summary_json"; then
        pass "summary JSON includes full usage shape when unavailable"
    else
        fail "summary JSON usage shape is incomplete"
    fi

    if echo "$out" | grep -q "effective quorum: 2/2 completed, 0 failed"; then
        pass "summarize prints expected quorum line"
    else
        fail "summarize quorum output incorrect: $out"
    fi

    rm -rf "$tmp"
}

test_summarize_start_failed_exit_semantics() {
    echo "=== Testing dx-review summarize start_failed semantics ==="

    local tmp fake out rc summary_json
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    export DX_REVIEW_FAKE_FORCE_START_FAILED=1
    unset DX_REVIEW_FAKE_REPORT_USAGE

    rm -rf /tmp/dx-review/bd-sf
    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-sf 2>&1)"
    rc=$?
    set -e

    summary_json="/tmp/dx-review/bd-sf/summary.json"
    if [[ "$rc" -eq 2 ]] && grep -q '"reviewer":"bd-sf.glm"' "$summary_json" && grep -q '"state":"start_failed"' "$summary_json"; then
        pass "summarize returns exit 2 and records start_failed reviewer"
    else
        fail "summarize start_failed semantics incorrect: rc=$rc output=$out"
    fi

    rm -rf "$tmp"
}

test_doctor_runs_both_profiles() {
    echo "=== Testing dx-review doctor profile coverage ==="

    local tmp fake worktree out
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    worktree="$tmp/worktree"
    mkdir -p "$worktree"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"

    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" doctor --worktree "$worktree" 2>&1)"
    if echo "$out" | grep -q "doctor profile=claude-code-review" && echo "$out" | grep -q "doctor profile=cc-glm-review" && ! echo "$out" | grep -q "doctor profile=opencode-review"; then
        pass "doctor checks primary review profiles without requiring fallback"
    else
        fail "doctor profile coverage incorrect: $out"
    fi

    rm -rf "$tmp"
}

test_template_pr_prompt_generation() {
    echo "=== Testing dx-review template + PR prompt generation ==="

    local tmp fake fake_gh worktree out rc prompt_file
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    fake_gh="$tmp/gh"
    worktree="$tmp/worktree"
    mkdir -p "$worktree"
    make_fake_runner "$fake"
    make_fake_gh "$fake_gh"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_OPENCODE_START_FAIL
    unset DX_REVIEW_FAKE_REPORT_USAGE

    set +e
    out="$(PATH="$tmp:$PATH" DX_RUNNER_BIN="$fake" DX_REVIEW_TEMPLATES_DIR="$SCRIPT_DIR/../templates/dx-review" "$DX_REVIEW" run --beads bd-prtpl --worktree "$worktree" --pr stars-end/agent-skills#554 --template smoke --read-only-shell 2>&1)"
    rc=$?
    set -e

    prompt_file="/tmp/dx-review/bd-prtpl/review.prompt"
    if [[ "$rc" -eq 0 && -f "$prompt_file" ]]; then
        pass "run --pr --template creates composed review prompt"
    else
        fail "run --pr --template failed: rc=$rc output=$out"
    fi

    if grep -q "Pull Request Metadata" "$prompt_file" \
        && grep -q "bd-icwpm: Fix dx-review authoritative worktree preflight" "$prompt_file" \
        && grep -q "Review Template: smoke" "$prompt_file" \
        && grep -q "Reviewer Output Schema" "$prompt_file" \
        && grep -q "Read-Only Review Mode" "$prompt_file"; then
        pass "composed prompt includes PR metadata, template, schema, and read-only contract"
    else
        fail "composed prompt missing expected sections"
    fi

    set +e
    out="$(PATH="$tmp:$PATH" DX_RUNNER_BIN="$fake" "$DX_REVIEW" run --beads bd-badtpl --worktree "$worktree" --template nope 2>&1)"
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]] && echo "$out" | grep -q "unknown template"; then
        pass "unknown templates fail closed"
    else
        fail "unknown template did not fail closed: rc=$rc output=$out"
    fi

    rm -rf "$tmp"
}

test_summarize_parses_log_schema_usage() {
    echo "=== Testing dx-review summarize parses reviewer log schema ==="

    local tmp fake out rc summary_json log_path
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_REPORT_USAGE

    rm -rf /tmp/dx-review/bd-logparse
    log_path="/tmp/dx-runner/cc-glm/bd-logparse.glm.log"
    mkdir -p "$(dirname "$log_path")"
    cat > "$log_path" <<'EOF'
**VERDICT: pass_with_findings**
**FINDINGS_COUNT: 2**
USAGE:
{"type":"step_finish","tokens":{"total":130,"input":101,"output":29},"cost":0.42}
**READ_ONLY_ENFORCEMENT: contract_only**
EOF

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-logparse 2>&1)"
    rc=$?
    set -e
    summary_json="/tmp/dx-review/bd-logparse/summary.json"

    if [[ "$rc" -eq 0 ]] \
        && grep -q '"verdict":"pass_with_findings"' "$summary_json" \
        && grep -q '"findings_count":2' "$summary_json" \
        && grep -q '"read_only_enforcement":"contract_only"' "$summary_json" \
        && grep -q '"total_tokens":130' "$summary_json" \
        && grep -q '"estimated_cost_usd":0.42' "$summary_json"; then
        pass "summarize parses verdict, findings, read-only status, and usage from logs"
    else
        fail "summarize did not parse log schema: rc=$rc output=$out"
    fi

    rm -f "$log_path"
    rm -rf "$tmp"
}

test_summarize_empty_success_is_unusable() {
    echo "=== Testing dx-review summarize treats empty success as unusable ==="

    local tmp fake out rc summary_json
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    export DX_REVIEW_FAKE_EMPTY_SUCCESS=1
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_REPORT_USAGE

    rm -rf /tmp/dx-review/bd-empty
    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-empty 2>&1)"
    rc=$?
    set -e
    summary_json="/tmp/dx-review/bd-empty/summary.json"

    if [[ "$rc" -eq 1 ]] \
        && grep -q '"reviewer":"bd-empty.glm"' "$summary_json" \
        && grep -q '"state":"review_unusable"' "$summary_json" \
        && grep -q '"usable_review":false' "$summary_json" \
        && grep -q '"review_status_reason":"missing_review_schema"' "$summary_json" \
        && echo "$out" | grep -q "effective quorum: 1/2 completed, 1 failed"; then
        pass "empty process success does not count as usable review quorum"
    else
        fail "empty process success was not degraded correctly: rc=$rc output=$out"
    fi

    unset DX_REVIEW_FAKE_EMPTY_SUCCESS
    rm -rf "$tmp"
}

test_summarize_ignores_prose_without_schema() {
    echo "=== Testing dx-review summarize ignores prose without reviewer schema ==="

    local tmp fake out rc summary_json log_path
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    export DX_REVIEW_FAKE_EMPTY_SUCCESS=1
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_REPORT_USAGE

    rm -rf /tmp/dx-review/bd-prose
    log_path="/tmp/dx-runner/cc-glm/bd-prose.glm.log"
    mkdir -p "$(dirname "$log_path")"
    cat > "$log_path" <<'EOF'
## Verdict
pass_with_findings

## Findings
- This is useful to a human, but it is not the required dx-review footer.
EOF

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-prose 2>&1)"
    rc=$?
    set -e
    summary_json="/tmp/dx-review/bd-prose/summary.json"

    if [[ "$rc" -eq 1 ]] \
        && grep -q '"reviewer":"bd-prose.glm"' "$summary_json" \
        && grep -q '"state":"review_unusable"' "$summary_json" \
        && grep -q '"usable_review":false' "$summary_json" \
        && grep -q '"review_status_reason":"missing_review_schema"' "$summary_json"; then
        pass "heading-style prose does not count as review quorum without explicit schema"
    else
        fail "prose without schema was counted as usable: rc=$rc output=$out"
    fi

    unset DX_REVIEW_FAKE_EMPTY_SUCCESS
    rm -f "$log_path"
    rm -rf "$tmp"
}

test_summarize_gemini_stopped_is_incomplete() {
    echo "=== Testing dx-review summarize treats stopped Gemini as incomplete ==="

    local tmp fake out rc summary_json run_dir
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    export DX_REVIEW_FAKE_GEMINI_STOPPED=1
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_REPORT_USAGE

    run_dir="/tmp/dx-review/bd-gemstop"
    rm -rf "$run_dir"
    mkdir -p "$run_dir"
    printf '## Read-Only Review Mode\n' > "$run_dir/review.prompt"

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-gemstop --gemini 2>&1)"
    rc=$?
    set -e
    summary_json="$run_dir/summary.json"

    if [[ "$rc" -eq 2 ]] \
        && grep -q '"reviewer":"bd-gemstop.gemini"' "$summary_json" \
        && grep -q '"state":"timeout_manual_stop"' "$summary_json" \
        && grep -q '"reason_code":"timeout_manual_stop"' "$summary_json" \
        && grep -q '"process_success":false' "$summary_json" \
        && grep -q '"usable_review":false' "$summary_json" \
        && grep -q '"mutation_count":1' "$summary_json" \
        && grep -q '"mutation_warning":"read_only_mutation_detected"' "$summary_json" \
        && echo "$out" | grep -q "effective quorum: 2/3 completed, 0 failed"; then
        pass "stopped optional Gemini lane is incomplete and mutation-warning aware"
    else
        fail "stopped Gemini lane was not classified correctly: rc=$rc output=$out"
    fi

    unset DX_REVIEW_FAKE_GEMINI_STOPPED
    rm -rf "$tmp"
}

test_summarize_rate_limit_failure_metadata() {
    echo "=== Testing dx-review summarize carries runtime rate-limit metadata ==="

    local tmp fake out rc summary_json summary_md
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    export DX_REVIEW_FAKE_RATE_LIMIT=1
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_REPORT_USAGE

    rm -rf /tmp/dx-review/bd-rate
    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-rate 2>&1)"
    rc=$?
    set -e
    summary_json="/tmp/dx-review/bd-rate/summary.json"
    summary_md="/tmp/dx-review/bd-rate/summary.md"

    if [[ "$rc" -eq 1 ]] \
        && grep -q '"reviewer":"bd-rate.glm"' "$summary_json" \
        && grep -q '"reason_code":"provider_rate_limited"' "$summary_json" \
        && grep -q '"failure_class":"provider_rate_limited"' "$summary_json" \
        && grep -q '"retryable":true' "$summary_json" \
        && grep -q '"provider_exit_code":1' "$summary_json" \
        && grep -q '"model":"glm-5"' "$summary_json" \
        && grep -q 'retry_after_backoff_or_switch_fallback_reviewer' "$summary_md" \
        && grep -q 'Rate limit reached' "$summary_md"; then
        pass "runtime rate limits are summarized with retryable root-cause metadata"
    else
        fail "runtime rate limit metadata missing: rc=$rc output=$out"
    fi

    unset DX_REVIEW_FAKE_RATE_LIMIT
    rm -rf "$tmp"
}

test_summarize_start_log_reason_when_metadata_missing() {
    echo "=== Testing dx-review summarize uses start log root cause when metadata is missing ==="

    local tmp fake out rc summary_json start_log
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    export DX_REVIEW_FAKE_REPORT_MISSING=1
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_REPORT_USAGE

    rm -rf /tmp/dx-review/bd-nometa
    mkdir -p /tmp/dx-review/bd-nometa
    start_log="/tmp/dx-review/bd-nometa/bd-nometa.glm.start.log"
    cat > "$start_log" <<'EOF'
reason_code=canonical_model_probe_timeout
model probe timed out for zhipuai/glm-5.1
EOF

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-nometa 2>&1)"
    rc=$?
    set -e
    summary_json="/tmp/dx-review/bd-nometa/summary.json"

    if [[ "$rc" -eq 2 ]] \
        && grep -q '"reviewer":"bd-nometa.glm"' "$summary_json" \
        && grep -q '"state":"start_failed"' "$summary_json" \
        && grep -q '"reason_code":"canonical_model_probe_timeout"' "$summary_json"; then
        pass "summarize preserves useful start-log root cause when runner metadata is missing"
    else
        fail "summarize did not preserve start-log root cause: rc=$rc output=$out"
    fi

    rm -rf "$tmp"
}

main() {
    test_parallel_start_and_glm_fallback
    test_summarize_default_reviewers_and_usage_unavailable
    test_summarize_start_failed_exit_semantics
    test_doctor_runs_both_profiles
    test_template_pr_prompt_generation
    test_summarize_parses_log_schema_usage
    test_summarize_empty_success_is_unusable
    test_summarize_ignores_prose_without_schema
    test_summarize_gemini_stopped_is_incomplete
    test_summarize_rate_limit_failure_metadata
    test_summarize_start_log_reason_when_metadata_missing
    echo ""
    echo "=== Summary ==="
    echo -e "Passed: ${GREEN}$PASS${NC}"
    echo -e "Failed: ${RED}$FAIL${NC}"
    [[ "$FAIL" -eq 0 ]]
}

main "$@"
