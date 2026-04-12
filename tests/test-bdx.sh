#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BDX="$ROOT/scripts/bdx"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass_count=0
fail_count=0

pass() {
  echo "PASS: $*"
  pass_count=$((pass_count + 1))
}

fail() {
  echo "FAIL: $*" >&2
  fail_count=$((fail_count + 1))
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$msg"
  else
    fail "$msg (missing '$needle')"
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq "$needle" "$file"; then
    pass "$msg"
  else
    fail "$msg (missing '$needle' in $file)"
  fi
}

run_expect_fail() {
  local expected="$1"
  shift
  local output rc
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    fail "expected failure: $*"
    return
  fi
  assert_contains "$output" "$expected" "failure includes '$expected'"
}

setup_fake_common() {
  local dir="$1"
  mkdir -p "$dir"

  cat >"$dir/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_BD_LOG:?missing FAKE_BD_LOG}"
printf 'BEADS_DIR=%s\n' "${BEADS_DIR:-}" >>"$FAKE_BD_LOG"
for arg in "$@"; do
  printf 'arg=%s\n' "$arg" >>"$FAKE_BD_LOG"
done
printf -- '---\n' >>"$FAKE_BD_LOG"
printf '{"ok":true}\n'
EOF
  chmod +x "$dir/bd"

  cat >"$dir/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_SSH_LOG:?missing FAKE_SSH_LOG}"
host="$1"
shift
printf 'host=%s\n' "$host" >>"$FAKE_SSH_LOG"
printf 'cmd=%s\n' "$*" >>"$FAKE_SSH_LOG"
bash -lc "$*"
EOF
  chmod +x "$dir/ssh"
}

setup_fake_flock() {
  local dir="$1"
  cat >"$dir/flock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_FLOCK_LOG:?missing FAKE_FLOCK_LOG}"
[[ "${1:-}" == "-w" ]] || exit 91
timeout="$2"
lock_path="$3"
shift 3
printf 'timeout=%s lock=%s\n' "$timeout" "$lock_path" >>"$FAKE_FLOCK_LOG"
exec "$@"
EOF
  chmod +x "$dir/flock"
}

test_remote_read_injection_safe() {
  local case_dir="$tmpdir/case1"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"
  local pwn="$case_dir/pwn"
  local pwn2="$case_dir/pwn2"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  FAKE_BD_LOG="$fake_bd_log" \
  FAKE_SSH_LOG="$fake_ssh_log" \
  HOME="$case_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  BDX_SSH_BIN="$fake_bin/ssh" \
  BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
  BDX_REMOTE_HOST="epyc12" \
  BDX_HOSTNAME="macbook" \
  "$BDX" show "\$(touch $pwn)" ";touch $pwn2" >/dev/null

  [[ ! -e "$pwn" && ! -e "$pwn2" ]] && pass "injection payloads were treated as data" || fail "shell payload executed"
  assert_file_contains "$fake_ssh_log" "host=epyc12" "remote host routed through ssh"
  assert_file_contains "$fake_bd_log" "BEADS_DIR=$case_dir/home/.beads-runtime/.beads" "remote BEADS_DIR enforced"
  assert_file_contains "$fake_bd_log" "arg=show" "read command reached bd"
  assert_file_contains "$fake_bd_log" "arg=\$(touch $pwn)" "dollar payload preserved literally"
  assert_file_contains "$fake_bd_log" "arg=;touch $pwn2" "semicolon payload preserved literally"
}

test_remote_write_uses_flock() {
  local case_dir="$tmpdir/case2"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"
  local fake_flock_log="$case_dir/fake-flock.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"
  setup_fake_flock "$fake_bin"

  FAKE_BD_LOG="$fake_bd_log" \
  FAKE_SSH_LOG="$fake_ssh_log" \
  FAKE_FLOCK_LOG="$fake_flock_log" \
  HOME="$case_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  BDX_SSH_BIN="$fake_bin/ssh" \
  BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
  BDX_REMOTE_HOST="epyc12" \
  BDX_HOSTNAME="macbook" \
  "$BDX" create --title "hello" >/dev/null

  assert_file_contains "$fake_flock_log" "lock=$case_dir/home/.beads-runtime/.locks/bdx-mutate.lock" "write path uses canonical remote lock"
  assert_file_contains "$fake_bd_log" "BEADS_DIR=$case_dir/home/.beads-runtime/.beads" "write path uses canonical BEADS_DIR"
  assert_file_contains "$fake_bd_log" "arg=create" "write command reached bd"
}

test_remote_write_mkdir_fallback() {
  local case_dir="$tmpdir/case3"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"
  local lock_dir="$case_dir/home/.beads-runtime/.locks/bdx-mutate.lock.dir"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  FAKE_BD_LOG="$fake_bd_log" \
  FAKE_SSH_LOG="$fake_ssh_log" \
  HOME="$case_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  BDX_DISABLE_FLOCK="1" \
  BDX_SSH_BIN="$fake_bin/ssh" \
  BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
  BDX_REMOTE_HOST="epyc12" \
  BDX_HOSTNAME="macbook" \
  "$BDX" note bd-test "note body" >/dev/null

  [[ ! -d "$lock_dir" ]] && pass "mkdir fallback lock is released" || fail "mkdir fallback lock directory leaked"
  assert_file_contains "$fake_bd_log" "arg=note" "write command reached bd via fallback lock"
}

test_rejections() {
  local case_dir="$tmpdir/case4"
  local fake_bin="$case_dir/bin"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  local base_env=(
    "HOME=$case_dir/home"
    "PATH=$fake_bin:/usr/bin:/bin"
    "FAKE_BD_LOG=$case_dir/fake-bd.log"
    "FAKE_SSH_LOG=$case_dir/fake-ssh.log"
    "BDX_SSH_BIN=$fake_bin/ssh"
    "BDX_REMOTE_HELPER=$ROOT/scripts/bdx-remote"
    "BDX_REMOTE_HOST=epyc12"
    "BDX_HOSTNAME=macbook"
  )

  run_expect_fail "rejected local-only command 'init'" env "${base_env[@]}" "$BDX" init
  run_expect_fail "rejected local-only dolt subcommand 'start'" env "${base_env[@]}" "$BDX" dolt start
  run_expect_fail "rejected risky config subcommand 'set'" env "${base_env[@]}" "$BDX" config set x y
  run_expect_fail "rejected unknown command 'xyz123'" env "${base_env[@]}" "$BDX" xyz123
}

test_local_on_epyc12() {
  local case_dir="$tmpdir/case5"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected ssh invocation" >&2
exit 99
EOF
  chmod +x "$fake_bin/ssh"

  FAKE_BD_LOG="$fake_bd_log" \
  FAKE_SSH_LOG="$fake_ssh_log" \
  HOME="$case_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  BDX_SSH_BIN="$fake_bin/ssh" \
  BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
  BDX_REMOTE_HOST="epyc12" \
  BDX_HOSTNAME="epyc12" \
  "$BDX" show bd-local >/dev/null

  assert_file_contains "$fake_bd_log" "arg=show" "epyc12 host runs local bd"
  assert_file_contains "$fake_bd_log" "BEADS_DIR=$case_dir/home/.beads-runtime/.beads" "epyc12 local path uses canonical BEADS_DIR"
}

main() {
  test_remote_read_injection_safe
  test_remote_write_uses_flock
  test_remote_write_mkdir_fallback
  test_rejections
  test_local_on_epyc12

  echo "Summary: pass=$pass_count fail=$fail_count"
  [[ $fail_count -eq 0 ]]
}

main "$@"
