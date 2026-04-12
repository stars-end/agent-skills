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
    echo "start:$beads:$profile:$(date +%s)" >> "$DX_REVIEW_FAKE_LOG"
    case "$profile" in
      claude-code-review)
        sleep "${DX_REVIEW_FAKE_CLAUDE_START_SEC:-3}"
        echo "started beads=$beads provider=claude-code"
        ;;
      opencode-review)
        if [[ "${DX_REVIEW_FAKE_OPENCODE_START_FAIL:-0}" == "1" ]]; then
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
    if [[ "$beads" == *.claude ]]; then
      echo '{"beads":"'"$beads"'","provider":"claude-code","state":"no_op_success","reason_code":"exit_zero_no_mutations"}'
    else
      echo '{"beads":"'"$beads"'","provider":"opencode","state":"exited_ok","reason_code":"process_exit_with_rc"}'
    fi
    ;;
  report)
    beads="$(arg_value --beads "$@")"
    echo '{"beads":"'"$beads"'","state":"no_op_success","reason_code":"exit_zero_no_mutations"}'
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

test_parallel_start_and_start_failure_terminal() {
    echo "=== Testing dx-review parallel start + start failure handling ==="

    local tmp fake worktree out rc claude_ts opencode_ts diff_sec
    tmp="$(mktemp -d)"
    fake="$tmp/dx-runner"
    worktree="$tmp/worktree"
    mkdir -p "$worktree"
    make_fake_runner "$fake"
    export DX_REVIEW_FAKE_LOG="$tmp/fake.log"
    export DX_REVIEW_FAKE_CLAUDE_START_SEC=3
    export DX_REVIEW_FAKE_OPENCODE_START_FAIL=1

    set +e
    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" run --beads bd-test --worktree "$worktree" --prompt "review only" --wait --timeout-sec 8 --poll-sec 1 2>&1)"
    rc=$?
    set -e

    claude_ts="$(awk -F: '$3=="claude-code-review"{print $4; exit}' "$DX_REVIEW_FAKE_LOG")"
    opencode_ts="$(awk -F: '$3=="opencode-review"{print $4; exit}' "$DX_REVIEW_FAKE_LOG")"
    diff_sec=$((opencode_ts - claude_ts))
    if [[ "$diff_sec" -lt 2 ]]; then
        pass "reviewers are started in parallel"
    else
        fail "reviewers appear serial (opencode started ${diff_sec}s after claude)"
    fi

    if [[ "$rc" -ne 0 ]] && echo "$out" | grep -q "state=start_failed" && echo "$out" | grep -q '"state":"start_failed"'; then
        pass "start failure is terminal and reported"
    else
        fail "start failure was not reported as terminal: rc=$rc output=$out"
    fi

    if echo "$DX_REVIEW_FAKE_LOG" | xargs cat 2>/dev/null | grep -q "check:bd-test.opencode"; then
        fail "start-failed reviewer was still polled"
    else
        pass "start-failed reviewer is not polled"
    fi

    if echo "$out" | grep -q "state=review_completed raw_state=no_op_success"; then
        pass "review no-op success is summarized as review_completed"
    else
        fail "review no-op success was not summarized clearly: $out"
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

    out="$(DX_RUNNER_BIN="$fake" "$DX_REVIEW" doctor --worktree "$worktree" 2>&1)"
    if echo "$out" | grep -q "doctor profile=claude-code-review" && echo "$out" | grep -q "doctor profile=opencode-review"; then
        pass "doctor checks both default review profiles"
    else
        fail "doctor did not check both profiles: $out"
    fi

    rm -rf "$tmp"
}

main() {
    test_parallel_start_and_start_failure_terminal
    test_doctor_runs_both_profiles
    echo ""
    echo "=== Summary ==="
    echo -e "Passed: ${GREEN}$PASS${NC}"
    echo -e "Failed: ${RED}$FAIL${NC}"
    [[ "$FAIL" -eq 0 ]]
}

main "$@"
