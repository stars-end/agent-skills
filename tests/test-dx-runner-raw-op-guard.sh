#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DX_RUNNER="$ROOT/scripts/dx-runner"

unsafe_prompt="$(mktemp)"
safe_prompt="$(mktemp)"
trap 'rm -f "$unsafe_prompt" "$safe_prompt"' EXIT

cat >"$unsafe_prompt" <<'EOF'
Run this sequence:
op read op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN
EOF

cat >"$safe_prompt" <<'EOF'
Run static lint and tests only.
Do not resolve secrets.
EOF

set +e
unsafe_output="$("$DX_RUNNER" start --beads bd-test --provider __missing__ --prompt-file "$unsafe_prompt" 2>&1)"
unsafe_rc=$?
set -e

if [[ $unsafe_rc -ne 21 ]]; then
    echo "FAIL: unsafe prompt expected exit 21, got $unsafe_rc" >&2
    echo "$unsafe_output" >&2
    exit 1
fi

if [[ "$unsafe_output" != *"reason_code=raw_op_forbidden_in_agent_context"* ]]; then
    echo "FAIL: unsafe prompt missing raw_op reason code" >&2
    echo "$unsafe_output" >&2
    exit 1
fi

set +e
safe_output="$("$DX_RUNNER" start --beads bd-test --provider __missing__ --prompt-file "$safe_prompt" 2>&1)"
safe_rc=$?
set -e

if [[ $safe_rc -ne 20 ]]; then
    echo "FAIL: safe prompt expected provider-not-found exit 20, got $safe_rc" >&2
    echo "$safe_output" >&2
    exit 1
fi

if [[ "$safe_output" == *"reason_code=raw_op_forbidden_in_agent_context"* ]]; then
    echo "FAIL: safe prompt unexpectedly triggered raw_op guard" >&2
    echo "$safe_output" >&2
    exit 1
fi

echo "PASS: dx-runner raw OP prompt guard rejects unsafe prompt and allows safe prompt"
