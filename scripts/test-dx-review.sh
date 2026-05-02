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
    cat > "$path" <<'EOF'
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
    provider="$(arg_value --provider "$@")"
    model="$(arg_value --model "$@")"
    beads="$(arg_value --beads "$@")"
    prompt_file="$(arg_value --prompt-file "$@")"
    echo "start:$beads:$provider:$model:$(date +%s)" >> "$DX_REVIEW_FAKE_LOG"
    echo "prompt_file:$beads:$prompt_file" >> "$DX_REVIEW_FAKE_LOG"
    case "$model" in
      opencode-go/kimi-k2.6)
        if [[ "${DX_REVIEW_FAKE_KIMI_START_FAIL:-0}" == "1" ]]; then
          mkdir -p "$state_dir"
          printf '1\n' > "$state_dir/${beads}.start_failed"
          echo "reason_code=model_unavailable"
          echo "preflight gate failed for provider opencode" >&2
          exit 22
        fi
        echo "started beads=$beads provider=opencode model=opencode-go/kimi-k2.6"
        ;;
      opencode-go/deepseek-v4-pro)
        if [[ "${DX_REVIEW_FAKE_DEEPSEEK_START_FAIL:-0}" == "1" ]]; then
          mkdir -p "$state_dir"
          printf '1\n' > "$state_dir/${beads}.start_failed"
          echo "reason_code=opencode_mise_untrusted"
          echo "preflight gate failed for provider opencode" >&2
          exit 21
        fi
        echo "started beads=$beads provider=opencode model=opencode-go/deepseek-v4-pro"
        ;;
      *)
        echo "started beads=$beads provider=$provider model=$model"
        ;;
    esac
    ;;
  check)
    beads="$(arg_value --beads "$@")"
    echo "check:$beads:$(date +%s)" >> "$DX_REVIEW_FAKE_LOG"
    if [[ "${DX_REVIEW_FAKE_REPORT_MISSING:-0}" == "1" && "$beads" == *.kimi ]]; then
      echo '{"beads":"'"$beads"'","state":"missing","reason_code":"no_meta"}'
      exit 1
    elif [[ -f "$state_dir/${beads}.start_failed" ]]; then
      provider="opencode"
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"start_failed","reason_code":"dx_runner_start_failed"}'
    elif [[ "${DX_REVIEW_FAKE_FORCE_START_FAILED:-0}" == "1" && "$beads" == *.kimi ]]; then
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"start_failed","reason_code":"dx_runner_start_failed"}'
    elif [[ "${DX_REVIEW_FAKE_DEEPSEEK_STOPPED:-0}" == "1" && "$beads" == *.deepseek ]]; then
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"stopped","reason_code":"manual_stop","mutation_count":1}'
    else
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"exited_ok","reason_code":"process_exit_with_rc"}'
    fi
    ;;
  report)
    beads="$(arg_value --beads "$@")"
    if [[ "${DX_REVIEW_FAKE_REPORT_MISSING:-0}" == "1" && "$beads" == *.kimi ]]; then
      echo '{"beads":"'"$beads"'","state":"missing","reason_code":"no_meta"}'
      exit 1
    elif [[ "${DX_REVIEW_FAKE_DEEPSEEK_STOPPED:-0}" == "1" && "$beads" == *.deepseek ]]; then
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"stopped","reason_code":"manual_stop","mutations":1}'
    elif [[ "${DX_REVIEW_FAKE_EMPTY_SUCCESS:-0}" == "1" && "$beads" == *.kimi ]]; then
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"exited_ok","reason_code":"process_exit_with_rc"}'
    elif [[ "${DX_REVIEW_FAKE_REPORT_USAGE:-0}" == "1" ]]; then
      provider="opencode"
      echo '{"beads":"'"$beads"'","provider":"'"$provider"'","state":"exited_ok","reason_code":"process_exit_with_rc","verdict":"pass_with_findings","findings_count":2,"read_only_enforcement":"contract_only","input_tokens":101,"output_tokens":29,"total_tokens":130,"estimated_cost_usd":0.42}'
    elif [[ "$beads" == *.kimi ]]; then
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"exited_ok","reason_code":"process_exit_with_rc","verdict":"pass_with_findings","findings_count":1,"read_only_enforcement":"contract_only"}'
    else
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"exited_ok","reason_code":"process_exit_with_rc","verdict":"pass_with_findings","findings_count":2,"read_only_enforcement":"contract_only"}'
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
EOF
    chmod +x "$path"
}

make_fake_gh() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "pr" ]]; then
  echo "unsupported fake gh command" >&2
  exit 2
fi
shift
case "${1:-}" in
  view)
    cat <<'JSON'
{"number":554,"url":"https://github.com/stars-end/agent-skills/pull/554","title":"bd-icwpm: Fix dx-review authoritative worktree preflight","state":"MERGED","baseRefName":"master","headRefName":"feature-bd-icwpm","baseRefOid":"79f2d464bbc052a4bb50fb2f4c77bb950e4a8554","headRefOid":"6771fc8c14cb93d03956a8c373cb328d9140c0ec","files":[{"path":"scripts/dx-review"},{"path":"scripts/test-dx-review.sh"}],"statusCheckRollup":[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]}
JSON
    ;;
  diff)
    echo " scripts/dx-review | 12 ++++++++++--"
    echo " 1 file changed, 10 insertions(+), 2 deletions(-)"
    ;;
  *)
    echo "unsupported fake gh pr command" >&2
    exit 2
    ;;
esac
EOF
    chmod +x "$path"
}

test_default_opencode_go_pair() {
    echo "=== Testing dx-review default OpenCode model pair ==="

    local tmp fake worktree out rc kimi_ts deepseek_ts
    local summary_json summary_md
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    worktree="$tmp/worktree"
    mkdir -p "$worktree"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    unset DX_REVIEW_FAKE_KIMI_START_FAIL
    unset DX_REVIEW_FAKE_DEEPSEEK_START_FAIL

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" run --beads bd-test --worktree "$worktree" --prompt "review only" --wait --timeout-sec 8 --poll-sec 1 2>&1)"
    rc=$?
    set -e

    kimi_ts="$(awk -F: '$4=="opencode-go/kimi-k2.6"{print $5; exit}' "$DX_REVIEW_FAKE_LOG")"
    deepseek_ts="$(awk -F: '$4=="opencode-go/deepseek-v4-pro"{print $5; exit}' "$DX_REVIEW_FAKE_LOG")"
    if [[ -n "$kimi_ts" && -n "$deepseek_ts" ]] \
        && [[ -z "$(awk -F: '$4!="opencode-go/kimi-k2.6" && $4!="opencode-go/deepseek-v4-pro"{print $4; exit}' "$DX_REVIEW_FAKE_LOG")" ]]; then
        pass "default run launches only Kimi and DeepSeek OpenCode reviewer lanes"
    else
        fail "default reviewer set incorrect: $out"
    fi

    if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "reviewer=bd-test.kimi" && echo "$out" | grep -q "reviewer=bd-test.deepseek"; then
        pass "wait loop reports both OpenCode reviewers"
    else
        fail "wait loop did not report both reviewers: rc=$rc output=$out"
    fi

    if echo "$out" | grep -q "state=exited_ok raw_state=exited_ok"; then
        pass "reviewer terminal states are surfaced during wait loop"
    else
        fail "reviewer terminal states were not summarized clearly: $out"
    fi

    summary_json="/tmp/dx-review/bd-test/summary.json"
    summary_md="/tmp/dx-review/bd-test/summary.md"
    if [[ -f "$summary_json" && -f "$summary_md" ]]; then
        pass "run --wait writes summary artifacts"
    else
        fail "run --wait did not write summary artifacts"
    fi

    if echo "$out" | grep -q "effective quorum: 2/2 completed, 0 failed" \
        && echo "$out" | grep -q "provider outcomes: 2 completed, 0 failed, 0 not reached" \
        && echo "$out" | grep -q "summary.json:"; then
        pass "run --wait prints effective quorum, provider outcomes, and summary artifact paths"
    else
        fail "run --wait missing quorum/summary output: $out"
    fi

    rm -rf "$tmp"
}

test_override_config_launches_three_reviewers() {
    echo "=== Testing dx-review YAML override with third reviewer ==="

    local tmp fake worktree out rc override_cfg
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    worktree="$tmp/worktree"
    mkdir -p "$worktree"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    unset DX_REVIEW_FAKE_KIMI_START_FAIL
    unset DX_REVIEW_FAKE_DEEPSEEK_START_FAIL

    override_cfg="$tmp/reviewers.yaml"
    cat > "$override_cfg" <<'EOF'
reviewers:
  - id: kimi
    provider: opencode
    model: opencode-go/kimi-k2.6
  - id: deepseek
    provider: opencode
    model: opencode-go/deepseek-v4-pro
  - id: qwen
    provider: opencode
    model: opencode-go/qwen3-coder
EOF

    set +e
    out="$(DX_RUNNER_BIN="$fake" DX_REVIEW_CONFIG="$override_cfg" "$DX_REVIEW" run --beads bd-three --worktree "$worktree" --prompt "review only" --wait --timeout-sec 8 --poll-sec 1 2>&1)"
    rc=$?
    set -e

    if [[ "$rc" -eq 0 ]] \
        && echo "$out" | grep -q "reviewer=bd-three.kimi" \
        && echo "$out" | grep -q "reviewer=bd-three.deepseek" \
        && echo "$out" | grep -q "reviewer=bd-three.qwen" \
        && echo "$out" | grep -q "effective quorum: 3/3 completed, 0 failed" \
        && [[ "$(awk -F: '$1=="start"{count++} END{print count+0}' "$DX_REVIEW_FAKE_LOG")" -eq 3 ]]; then
        pass "override config adds a third reviewer without shell/script edits"
    else
        fail "override config did not launch all three reviewers: rc=$rc output=$out"
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
    unset DX_REVIEW_FAKE_KIMI_START_FAIL
    unset DX_REVIEW_FAKE_DEEPSEEK_START_FAIL
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
    if [[ "$rc" -eq 2 ]] && grep -q '"reviewer":"bd-sf.kimi"' "$summary_json" && grep -q '"state":"start_failed"' "$summary_json"; then
        pass "summarize returns exit 2 and records start_failed reviewer"
    else
        fail "summarize start_failed semantics incorrect: rc=$rc output=$out"
    fi

    rm -rf "$tmp"
}

test_doctor_uses_configured_provider_model_pairs() {
    echo "=== Testing dx-review doctor provider/model coverage ==="

    local tmp fake worktree out
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    worktree="$tmp/worktree"
    mkdir -p "$worktree"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"

    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" doctor --worktree "$worktree" 2>&1)"
    if echo "$out" | grep -q "doctor reviewer=kimi provider=opencode model=opencode-go/kimi-k2.6" \
        && echo "$out" | grep -q "doctor reviewer=deepseek provider=opencode model=opencode-go/deepseek-v4-pro" \
        && ! echo "$out" | grep -q "doctor reviewer=qwen"; then
        pass "doctor checks configured reviewer provider/model pairs"
    else
        fail "doctor provider/model coverage incorrect: $out"
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
    unset DX_REVIEW_FAKE_KIMI_START_FAIL
    unset DX_REVIEW_FAKE_DEEPSEEK_START_FAIL
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
    log_path="/tmp/dx-runner/opencode/bd-logparse.kimi.log"
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
        && grep -q '"findings_count":1' "$summary_json" \
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
        && grep -q '"reviewer":"bd-empty.kimi"' "$summary_json" \
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
    log_path="/tmp/dx-runner/opencode/bd-prose.kimi.log"
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
        && grep -q '"reviewer":"bd-prose.kimi"' "$summary_json" \
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

test_summarize_deepseek_stopped_is_incomplete() {
    echo "=== Testing dx-review summarize treats stopped DeepSeek as incomplete ==="

    local tmp fake out rc summary_json run_dir
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_STATE_DIR="$tmp/state"
    export DX_REVIEW_FAKE_DEEPSEEK_STOPPED=1
    unset DX_REVIEW_FAKE_FORCE_START_FAILED
    unset DX_REVIEW_FAKE_REPORT_USAGE

    run_dir="/tmp/dx-review/bd-deepstop"
    rm -rf "$run_dir"
    mkdir -p "$run_dir"
    printf '## Read-Only Review Mode\n' > "$run_dir/review.prompt"

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-deepstop 2>&1)"
    rc=$?
    set -e
    summary_json="$run_dir/summary.json"

    if [[ "$rc" -eq 2 ]] \
        && grep -q '"reviewer":"bd-deepstop.deepseek"' "$summary_json" \
        && grep -q '"state":"timeout_manual_stop"' "$summary_json" \
        && grep -q '"reason_code":"timeout_manual_stop"' "$summary_json" \
        && grep -q '"process_success":false' "$summary_json" \
        && grep -q '"usable_review":false' "$summary_json" \
        && grep -q '"mutation_count":1' "$summary_json" \
        && grep -q '"mutation_warning":"read_only_mutation_detected"' "$summary_json" \
        && echo "$out" | grep -q "effective quorum: 1/2 completed, 0 failed"; then
        pass "stopped DeepSeek lane is incomplete and mutation-warning aware"
    else
        fail "stopped DeepSeek lane was not classified correctly: rc=$rc output=$out"
    fi

    unset DX_REVIEW_FAKE_DEEPSEEK_STOPPED
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
    start_log="/tmp/dx-review/bd-nometa/bd-nometa.kimi.start.log"
    cat > "$start_log" <<'EOF'
reason_code=canonical_model_probe_timeout
model probe timed out for opencode-go/kimi-k2.6
EOF

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" summarize --beads bd-nometa 2>&1)"
    rc=$?
    set -e
    summary_json="/tmp/dx-review/bd-nometa/summary.json"

    if [[ "$rc" -eq 2 ]] \
        && grep -q '"reviewer":"bd-nometa.kimi"' "$summary_json" \
        && grep -q '"state":"start_failed"' "$summary_json" \
        && grep -q '"reason_code":"canonical_model_probe_timeout"' "$summary_json"; then
        pass "summarize preserves useful start-log root cause when runner metadata is missing"
    else
        fail "summarize did not preserve start-log root cause: rc=$rc output=$out"
    fi

    rm -rf "$tmp"
}

main() {
    test_default_opencode_go_pair
    test_override_config_launches_three_reviewers
    test_summarize_default_reviewers_and_usage_unavailable
    test_summarize_start_failed_exit_semantics
    test_doctor_uses_configured_provider_model_pairs
    test_template_pr_prompt_generation
    test_summarize_parses_log_schema_usage
    test_summarize_empty_success_is_unusable
    test_summarize_ignores_prose_without_schema
    test_summarize_deepseek_stopped_is_incomplete
    test_summarize_start_log_reason_when_metadata_missing
    echo ""
    echo "=== Summary ==="
    echo -e "Passed: ${GREEN}$PASS${NC}"
    echo -e "Failed: ${RED}$FAIL${NC}"
    [[ "$FAIL" -eq 0 ]]
}

main "$@"
