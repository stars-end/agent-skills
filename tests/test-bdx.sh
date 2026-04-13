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
while [[ "${1:-}" == "-o" ]]; do
  shift 2
done
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

setup_fake_timeout() {
  local dir="$1"
  cat >"$dir/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
shift
exec "$@"
EOF
  chmod +x "$dir/timeout"
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

test_help_exits_zero() {
  "$BDX" --help >/dev/null 2>&1 && pass "help exits zero" || fail "help exits non-zero"
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
  setup_fake_timeout "$fake_bin"

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

test_memory_commands() {
  local case_dir="$tmpdir/case_mem"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"
  local fake_flock_log="$case_dir/fake-flock.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"
  setup_fake_flock "$fake_bin"
  setup_fake_timeout "$fake_bin"

  FAKE_BD_LOG="$fake_bd_log" \
  FAKE_SSH_LOG="$fake_ssh_log" \
  FAKE_FLOCK_LOG="$fake_flock_log" \
  HOME="$case_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  BDX_SSH_BIN="$fake_bin/ssh" \
  BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
  BDX_REMOTE_HOST="epyc12" \
  BDX_HOSTNAME="macbook" \
  "$BDX" remember "fleet" "bdx is canonical" >/dev/null

  FAKE_BD_LOG="$fake_bd_log" \
  FAKE_SSH_LOG="$fake_ssh_log" \
  FAKE_FLOCK_LOG="$fake_flock_log" \
  HOME="$case_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  BDX_SSH_BIN="$fake_bin/ssh" \
  BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
  BDX_REMOTE_HOST="epyc12" \
  BDX_HOSTNAME="macbook" \
  "$BDX" memories "fleet" >/dev/null

  assert_file_contains "$fake_flock_log" "lock=$case_dir/home/.beads-runtime/.locks/bdx-mutate.lock" "remember uses write lock"
  assert_file_contains "$fake_bd_log" "arg=remember" "remember command allowed"
  assert_file_contains "$fake_bd_log" "arg=memories" "memories command allowed"
}

test_comments_issue_id_read_shape() {
  local case_dir="$tmpdir/case_comments_read"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

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
  "$BDX" comments bd-test --json >/dev/null

  assert_file_contains "$fake_ssh_log" "host=epyc12" "comments <id> routes as remote read"
  assert_file_contains "$fake_bd_log" "arg=comments" "comments command reached bd"
  assert_file_contains "$fake_bd_log" "arg=bd-test" "comments issue id preserved"
  assert_file_contains "$fake_bd_log" "arg=--json" "comments JSON flag preserved"
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
  run_expect_fail "rejected comments subcommand 'delete'" env "${base_env[@]}" "$BDX" comments delete bd-test c1
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

test_local_epyc12_write_uses_lock() {
  local case_dir="$tmpdir/case6"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"
  local fake_flock_log="$case_dir/fake-flock.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"
  setup_fake_flock "$fake_bin"
  setup_fake_timeout "$fake_bin"

  cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected ssh invocation" >&2
exit 99
EOF
  chmod +x "$fake_bin/ssh"

  FAKE_BD_LOG="$fake_bd_log" \
  FAKE_SSH_LOG="$fake_ssh_log" \
  FAKE_FLOCK_LOG="$fake_flock_log" \
  HOME="$case_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  BDX_SSH_BIN="$fake_bin/ssh" \
  BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
  BDX_REMOTE_HOST="epyc12" \
  BDX_HOSTNAME="epyc12" \
  "$BDX" comments add bd-local "locked local write" >/dev/null

  assert_file_contains "$fake_flock_log" "lock=$case_dir/home/.beads-runtime/.locks/bdx-mutate.lock" "epyc12 local write uses lock"
  assert_file_contains "$fake_bd_log" "arg=comments" "epyc12 local write reaches bd"
}

test_tailscale_hostname_detects_epyc12() {
  local case_dir="$tmpdir/case_ts"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  cat >"$fake_bin/tailscale" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "status" && "${2:-}" == "--json" ]]; then
  printf '{"Self":{"HostName":"epyc12","DNSName":"epyc12.sable-cliff.ts.net."}}\n'
else
  exit 2
fi
EOF
  chmod +x "$fake_bin/tailscale"

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
  BDX_HOSTNAME="v2202601262171429561" \
  "$BDX" show bd-local >/dev/null

  assert_file_contains "$fake_bd_log" "arg=show" "tailscale hostname detects epyc12 as local hub"
}

test_tailscale_peer_does_not_make_spoke_local() {
  local case_dir="$tmpdir/case_ts_peer"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  cat >"$fake_bin/tailscale" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "status" && "${2:-}" == "--json" ]]; then
  printf '{"Self":{"HostName":"mbp","DNSName":"mbp.sable-cliff.ts.net."},"Peer":{"nodekey:x":{"HostName":"epyc12","DNSName":"epyc12.sable-cliff.ts.net."}}}\n'
else
  exit 2
fi
EOF
  chmod +x "$fake_bin/tailscale"

  FAKE_BD_LOG="$fake_bd_log" \
  FAKE_SSH_LOG="$fake_ssh_log" \
  HOME="$case_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  BDX_SSH_BIN="$fake_bin/ssh" \
  BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
  BDX_REMOTE_HOST="epyc12" \
  BDX_HOSTNAME="mbp" \
  "$BDX" show bd-remote >/dev/null

  assert_file_contains "$fake_ssh_log" "host=epyc12" "tailscale peer epyc12 does not make spoke local"
  assert_file_contains "$fake_bd_log" "arg=show" "spoke routes through remote helper"
}

test_remote_helper_revalidates_allowlist() {
  local case_dir="$tmpdir/case7"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  local output rc
  set +e
  output="$(
    printf 'doctor\0--fix\0' | \
      FAKE_BD_LOG="$fake_bd_log" \
      HOME="$case_dir/home" \
      PATH="$fake_bin:/usr/bin:/bin" \
      "$ROOT/scripts/bdx-remote" --mode=write 2>&1
  )"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] && pass "remote helper rejects direct disallowed command" || fail "remote helper allowed doctor --fix"
  assert_contains "$output" "rejected local-only command 'doctor'" "remote helper rejection message is explicit"
  [[ ! -f "$fake_bd_log" ]] && pass "remote helper did not call bd for rejected command" || fail "remote helper called bd for rejected command"
}

test_remote_rejects_file_bearing_flags_with_clear_error() {
  local case_dir="$tmpdir/case8"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  local -a test_cases=(
    "--body-file /tmp/local.md"
    "--description-file /tmp/local-description.md"
    "--design-file /tmp/local-design.md"
    "--file /tmp/local.md"
    "--graph /tmp/local.dot"
    "--stdin"
  )

  local case_spec output rc
  for case_spec in "${test_cases[@]}"; do
    rm -f "$fake_ssh_log" "$fake_bd_log"
    set +e
    output="$(
      FAKE_BD_LOG="$fake_bd_log" \
      FAKE_SSH_LOG="$fake_ssh_log" \
      HOME="$case_dir/home" \
      PATH="$fake_bin:/usr/bin:/bin" \
      BDX_SSH_BIN="$fake_bin/ssh" \
      BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
      BDX_REMOTE_HOST="epyc12" \
      BDX_HOSTNAME="macbook" \
      "$BDX" create --title "remote file flag" ${case_spec} 2>&1
    )"
    rc=$?
    set -e

    [[ $rc -ne 0 ]] && pass "remote file-bearing case rejected: ${case_spec}" || fail "remote file-bearing case should fail: ${case_spec}"
    if [[ "$case_spec" == "--stdin" ]]; then
      assert_contains "$output" "'--stdin' body streaming is not supported" "stdin rejection message is explicit"
    else
      assert_contains "$output" "local file-bearing flag" "file-bearing rejection message is explicit"
    fi
    [[ ! -f "$fake_ssh_log" ]] && pass "file-bearing preflight stops before ssh (${case_spec})" || fail "file-bearing preflight unexpectedly called ssh (${case_spec})"
    [[ ! -f "$fake_bd_log" ]] && pass "file-bearing preflight stops before bd (${case_spec})" || fail "file-bearing preflight unexpectedly called bd (${case_spec})"
  done
}

test_remote_rejects_metadata_file_expansion_with_clear_error() {
  local case_dir="$tmpdir/case8b"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  local -a test_cases=(
    "--metadata @/tmp/local-meta.json"
    "--metadata=@/tmp/local-meta.json"
  )

  local case_spec output rc
  for case_spec in "${test_cases[@]}"; do
    rm -f "$fake_ssh_log" "$fake_bd_log"
    set +e
    output="$(
      FAKE_BD_LOG="$fake_bd_log" \
      FAKE_SSH_LOG="$fake_ssh_log" \
      HOME="$case_dir/home" \
      PATH="$fake_bin:/usr/bin:/bin" \
      BDX_SSH_BIN="$fake_bin/ssh" \
      BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
      BDX_REMOTE_HOST="epyc12" \
      BDX_HOSTNAME="macbook" \
      "$BDX" create --title "remote metadata file" ${case_spec} 2>&1
    )"
    rc=$?
    set -e

    [[ $rc -ne 0 ]] && pass "remote metadata file expansion rejected: ${case_spec}" || fail "remote metadata file expansion should fail: ${case_spec}"
    assert_contains "$output" "metadata file expansion" "metadata file rejection message is explicit"
    [[ ! -f "$fake_ssh_log" ]] && pass "metadata-file preflight stops before ssh (${case_spec})" || fail "metadata-file preflight unexpectedly called ssh (${case_spec})"
    [[ ! -f "$fake_bd_log" ]] && pass "metadata-file preflight stops before bd (${case_spec})" || fail "metadata-file preflight unexpectedly called bd (${case_spec})"
  done
}

test_json_error_for_local_file_flag() {
  local case_dir="$tmpdir/case10"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  local output rc
  set +e
  output="$(
    FAKE_BD_LOG="$fake_bd_log" \
    FAKE_SSH_LOG="$fake_ssh_log" \
    HOME="$case_dir/home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    BDX_SSH_BIN="$fake_bin/ssh" \
    BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
    BDX_REMOTE_HOST="epyc12" \
    BDX_HOSTNAME="macbook" \
    BDX_JSON_ERRORS=1 \
    "$BDX" create --title "remote file flag" --body-file /tmp/local.md --json 2>&1
  )"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] && pass "JSON error file-bearing case is rejected" || fail "JSON error file-bearing case should fail"
  assert_contains "$output" '"reason_code":"local_file_arg_unsupported"' "file-bearing rejection exposes reason_code"
  assert_contains "$output" '"ok":false' "file-bearing rejection exposes structured JSON"
  [[ ! -f "$fake_ssh_log" ]] && pass "JSON file-bearing preflight stops before ssh" || fail "JSON file-bearing preflight unexpectedly called ssh"
}

test_remote_read_timeout_json() {
  local case_dir="$tmpdir/case11"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"

  mkdir -p "$fake_bin" "$case_dir/home"

  cat >"$fake_bin/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_BD_LOG:?missing FAKE_BD_LOG}"
printf 'arg=%s\n' "$1" >>"$FAKE_BD_LOG"
sleep 3
EOF
  chmod +x "$fake_bin/bd"

  local output rc
  set +e
  output="$(
    printf 'show\0bd-slow\0--json\0' | \
      FAKE_BD_LOG="$fake_bd_log" \
      HOME="$case_dir/home" \
      PATH="$fake_bin:/usr/bin:/bin" \
      BDX_COMMAND_TIMEOUT_SECONDS=1 \
      BDX_JSON_ERRORS=1 \
      "$ROOT/scripts/bdx-remote" --mode=read 2>&1
  )"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] && pass "remote read timeout fails" || fail "remote read timeout should fail"
  assert_contains "$output" '"reason_code":"query_timeout"' "remote read timeout exposes reason_code"
}

test_local_read_timeout_json() {
  local case_dir="$tmpdir/case11local"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"

  mkdir -p "$fake_bin" "$case_dir/home"

  cat >"$fake_bin/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_BD_LOG:?missing FAKE_BD_LOG}"
printf 'arg=%s\n' "$1" >>"$FAKE_BD_LOG"
sleep 3
EOF
  chmod +x "$fake_bin/bd"

  cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected ssh invocation" >&2
exit 99
EOF
  chmod +x "$fake_bin/ssh"

  local output rc
  set +e
  output="$(
    FAKE_BD_LOG="$fake_bd_log" \
    HOME="$case_dir/home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    BDX_SSH_BIN="$fake_bin/ssh" \
    BDX_REMOTE_HOST="epyc12" \
    BDX_HOSTNAME="epyc12" \
    BDX_COMMAND_TIMEOUT_SECONDS=1 \
    BDX_JSON_ERRORS=1 \
    "$BDX" show bd-slow --json 2>&1
  )"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] && pass "local hub read timeout fails" || fail "local hub read timeout should fail"
  assert_contains "$output" '"reason_code":"query_timeout"' "local hub read timeout exposes reason_code"
}

test_remote_write_timeout_json() {
  local case_dir="$tmpdir/case11b"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_flock_log="$case_dir/fake-flock.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"
  setup_fake_flock "$fake_bin"

  cat >"$fake_bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 124
EOF
  chmod +x "$fake_bin/timeout"

  local output rc
  set +e
  output="$(
    printf 'create\0--title\0slow write\0--json\0' | \
      FAKE_BD_LOG="$fake_bd_log" \
      FAKE_FLOCK_LOG="$fake_flock_log" \
      HOME="$case_dir/home" \
      PATH="$fake_bin:/usr/bin:/bin" \
      BDX_COMMAND_TIMEOUT_SECONDS=1 \
      BDX_JSON_ERRORS=1 \
      "$ROOT/scripts/bdx-remote" --mode=write 2>&1
  )"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] && pass "remote write timeout fails" || fail "remote write timeout should fail"
  assert_contains "$output" '"reason_code":"mutation_timeout"' "remote write timeout exposes reason_code"
  assert_file_contains "$fake_flock_log" "lock=$case_dir/home/.beads-runtime/.locks/bdx-mutate.lock" "remote write timeout uses flock path"
}

test_preflight_json_uses_targeted_probes() {
  local case_dir="$tmpdir/case12"
  local fake_bin="$case_dir/bin"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

  mkdir -p "$fake_bin" "$case_dir/home"
  setup_fake_common "$fake_bin"

  local output
  output="$(
    FAKE_BD_LOG="$fake_bd_log" \
    FAKE_SSH_LOG="$fake_ssh_log" \
    HOME="$case_dir/home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    BDX_SSH_BIN="$fake_bin/ssh" \
    BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
    BDX_REMOTE_HOST="epyc12" \
    BDX_HOSTNAME="macbook" \
    "$BDX" preflight --json --probe-id bd-probe
  )"

  assert_contains "$output" '"ok":true' "preflight reports ok JSON"
  assert_contains "$output" '"reason_code":"ok"' "preflight reports ok reason"
  assert_file_contains "$fake_bd_log" "arg=dolt" "preflight checks Dolt connectivity"
  assert_file_contains "$fake_bd_log" "arg=show" "preflight uses targeted show"
  if grep -Fq "arg=ready" "$fake_bd_log"; then
    fail "preflight should not call broad ready"
  else
    pass "preflight avoids broad ready"
  fi
}

test_symlinked_bdx_finds_preflight_helper() {
  local case_dir="$tmpdir/case_symlink_preflight"
  local fake_bin="$case_dir/bin"
  local link_dir="$case_dir/links"
  local fake_bd_log="$case_dir/fake-bd.log"
  local fake_ssh_log="$case_dir/fake-ssh.log"

  mkdir -p "$fake_bin" "$case_dir/home" "$link_dir"
  setup_fake_common "$fake_bin"
  ln -s "$BDX" "$link_dir/bdx"

  local output
  output="$(
    FAKE_BD_LOG="$fake_bd_log" \
    FAKE_SSH_LOG="$fake_ssh_log" \
    HOME="$case_dir/home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    BDX_SSH_BIN="$fake_bin/ssh" \
    BDX_REMOTE_HELPER="$ROOT/scripts/bdx-remote" \
    BDX_REMOTE_HOST="epyc12" \
    BDX_HOSTNAME="macbook" \
    "$link_dir/bdx" preflight --json --probe-id bd-probe
  )"

  assert_contains "$output" '"ok":true' "symlinked bdx finds preflight helper"
  assert_file_contains "$fake_bd_log" "arg=dolt" "symlinked bdx preflight checks Dolt connectivity"
  assert_file_contains "$fake_bd_log" "arg=show" "symlinked bdx preflight uses targeted show"
}

main() {
  test_help_exits_zero
  test_remote_read_injection_safe
  test_remote_write_uses_flock
  test_remote_write_mkdir_fallback
  test_memory_commands
  test_comments_issue_id_read_shape
  test_rejections
  test_local_on_epyc12
  test_local_epyc12_write_uses_lock
  test_tailscale_hostname_detects_epyc12
  test_tailscale_peer_does_not_make_spoke_local
  test_remote_helper_revalidates_allowlist
  test_remote_rejects_file_bearing_flags_with_clear_error
  test_remote_rejects_metadata_file_expansion_with_clear_error
  test_json_error_for_local_file_flag
  test_remote_read_timeout_json
  test_local_read_timeout_json
  test_remote_write_timeout_json
  test_preflight_json_uses_targeted_probes
  test_symlinked_bdx_finds_preflight_helper

  echo "Summary: pass=$pass_count fail=$fail_count"
  [[ $fail_count -eq 0 ]]
}

main "$@"
