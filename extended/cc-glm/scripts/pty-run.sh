#!/usr/bin/env bash
# pty-run.sh
#
# PTY-backed command runner for capturing output from programs that
# require a TTY or behave differently without one.
#
# Usage:
#   pty-run.sh --output /path/to/log -- command [args...]
#   pty-run.sh --output /path/to/log --timeout 60 -- command [args...]
#
# Falls back to direct execution if PTY is unavailable.
#
# Exit codes:
#   0 - success
#   1 - general error
#   124 - timeout
#   125 - PTY setup failed

set -euo pipefail

OUTPUT_FILE=""
TIMEOUT_SECS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECS="${2:-0}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      cat <<'EOF'
pty-run.sh - PTY-backed command runner

Usage:
  pty-run.sh --output /path/to/log -- command [args...]
  pty-run.sh --output /path/to/log --timeout 60 -- command [args...]

Options:
  --output FILE   Write captured output to FILE (required)
  --timeout N     Timeout in seconds (0 = no timeout, default)
  --              Separator before command

Falls back to direct execution if Python pty module is unavailable.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Error: no command specified" >&2
  exit 2
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  echo "Error: --output is required" >&2
  exit 2
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")" 2>/dev/null || true

# Serialize command args to base64 to avoid any escaping issues
# Python will decode and use json.loads
CMD_BASE64=$(printf '%s\n' "$@" | base64)

# Try PTY-backed execution via Python
run_with_pty() {
  local output_file="$1"
  local timeout_secs="$2"
  local cmd_base64="$3"

  python3 - "$output_file" "$timeout_secs" "$cmd_base64" << 'PYEOF'
import os
import pty
import select
import subprocess
import sys
import base64
import json

output_file = sys.argv[1]
timeout_secs = int(sys.argv[2])
cmd_base64 = sys.argv[3]

# Decode base64 command (newline-separated args)
try:
    cmd_json = base64.b64decode(cmd_base64).decode('utf-8')
    # Split on newlines, filter empty
    cmd = [line for line in cmd_json.split('\n') if line]
except Exception as e:
    print(f"Failed to decode command: {e}", file=sys.stderr)
    sys.exit(125)

try:
    # Create PTY
    master_fd, slave_fd = pty.openpty()

    # Start subprocess with PTY as stdout/stderr
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=slave_fd,
        stderr=slave_fd,
        close_fds=True,
        start_new_session=True
    )

    # Close slave in parent
    os.close(slave_fd)

    # Stream output with optional timeout so watchdog can observe log growth.
    output_file_handle = open(output_file, 'wb')
    deadline = None
    if timeout_secs > 0:
        import time
        deadline = time.time() + timeout_secs

    while True:
        if deadline:
            remaining = deadline - time.time()
            if remaining <= 0:
                proc.kill()
                proc.wait()
                sys.exit(124)  # timeout exit code
            ready, _, _ = select.select([master_fd], [], [], min(1.0, remaining))
        else:
            ready, _, _ = select.select([master_fd], [], [], 1.0)

        if ready:
            try:
                data = os.read(master_fd, 4096)
                if not data:
                    break
                output_file_handle.write(data)
                output_file_handle.flush()
            except OSError:
                break

        # Check if process is done
        if proc.poll() is not None:
            # Drain remaining output
            while True:
                try:
                    data = os.read(master_fd, 4096)
                    if not data:
                        break
                    output_file_handle.write(data)
                    output_file_handle.flush()
                except OSError:
                    break
            break

    os.close(master_fd)
    output_file_handle.close()

    # Wait for process and get exit code
    proc.wait()
    sys.exit(proc.returncode)

except Exception as e:
    print(f"PTY execution failed: {e}", file=sys.stderr)
    sys.exit(125)  # PTY setup failed
PYEOF
}

# Fallback: direct execution
run_direct() {
  local output_file="$1"
  local timeout_secs="$2"
  shift 2

  if [[ "$timeout_secs" -gt 0 ]]; then
    timeout "$timeout_secs" "$@" >> "$output_file" 2>&1
  else
    "$@" >> "$output_file" 2>&1
  fi
}

# Try PTY first, fall back to direct
if python3 -c "import pty" 2>/dev/null; then
  run_with_pty "$OUTPUT_FILE" "$TIMEOUT_SECS" "$CMD_BASE64"
  exit $?
else
  echo "Warning: Python pty module unavailable, using direct execution" >&2
  run_direct "$OUTPUT_FILE" "$TIMEOUT_SECS" "$@"
  exit $?
fi
