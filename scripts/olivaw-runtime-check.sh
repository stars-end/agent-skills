#!/usr/bin/env bash
set -euo pipefail

profile="${1:-olivaw}"
label="ai.hermes.gateway-${profile}"
uid="$(id -u)"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

launchctl_rc=0
launchctl_out="$(launchctl print "gui/${uid}/${label}" 2>&1)" || launchctl_rc=$?

gateway_rc=0
gateway_out="$(hermes -p "${profile}" gateway status 2>&1)" || gateway_rc=$?

pid="$(pgrep -f "hermes_cli.main --profile ${profile} gateway run" | head -n1 || true)"
public_listeners="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '/hermes|python/ && $9 !~ /127\\.0\\.0\\.1|localhost|::1/ {print $0}' || true)"

ok=true
reason="ok"

if [[ "${launchctl_rc}" -ne 0 ]]; then
  ok=false
  reason="launchagent_not_loaded"
elif [[ "${gateway_rc}" -ne 0 ]]; then
  ok=false
  reason="gateway_status_failed"
elif [[ -z "${pid}" ]]; then
  ok=false
  reason="gateway_pid_missing"
elif [[ -n "${public_listeners}" ]]; then
  ok=false
  reason="public_listener_detected"
fi

cat <<JSON
{
  "ok": ${ok},
  "profile": "$(printf '%s' "${profile}")",
  "label": "$(printf '%s' "${label}")",
  "pid": "$(printf '%s' "${pid}")",
  "reason": "$(printf '%s' "${reason}")",
  "launchctl_rc": ${launchctl_rc},
  "gateway_rc": ${gateway_rc},
  "launchctl_output": $(printf '%s' "${launchctl_out}" | json_escape),
  "gateway_output": $(printf '%s' "${gateway_out}" | json_escape),
  "public_listeners": $(printf '%s' "${public_listeners}" | json_escape),
  "log_paths": [
    "$HOME/.hermes/profiles/${profile}/logs/gateway.log",
    "$HOME/.hermes/profiles/${profile}/logs/gateway.error.log"
  ]
}
JSON

if [[ "${ok}" != true ]]; then
  exit 1
fi
