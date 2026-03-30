#!/usr/bin/env bash
# Shared Railway CLI utilities for Claude plugin skills

check_railway_cli() {
  if command -v railway &>/dev/null; then
    echo '{"installed": true, "path": "'$(which railway)'"}'
    return 0
  else
    echo '{"installed": false, "error": "cli_missing"}'
    return 1
  fi
}

check_railway_auth() {
  local whoami_output
  whoami_output=$(railway whoami --json 2>&1)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "$whoami_output"
    return 0
  else
    echo '{"authenticated": false, "error": "not_authenticated"}'
    return 1
  fi
}

check_railway_linked() {
  local status_output
  status_output=$(railway status --json 2>&1)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]] && [[ "$status_output" != *"No linked project"* ]] && [[ "$status_output" != *"error"* ]]; then
    echo "$status_output"
    return 0
  else
    echo '{"linked": false, "error": "not_linked"}'
    return 1
  fi
}

railway_preflight() {
  # Check CLI installed
  if ! command -v railway &>/dev/null; then
    echo '{"ready": false, "error": "cli_missing"}'
    return 1
  fi

  # Check authenticated
  local auth_check
  auth_check=$(railway whoami --json 2>&1)
  if [[ $? -ne 0 ]]; then
    echo '{"ready": false, "error": "not_authenticated"}'
    return 1
  fi

  # Check project linked
  local status_output
  status_output=$(railway status --json 2>&1)
  if [[ $? -ne 0 ]] || [[ "$status_output" == *"No linked project"* ]]; then
    echo '{"ready": false, "error": "not_linked"}'
    return 1
  fi

  # All checks passed - return status
  echo "$status_output"
  return 0
}

check_deploy_freshness() {
  # Check whether the live deployment matches origin/master.
  #
  # Preference order (runtime truth first):
  #   1. Runtime endpoint /commit-info or equivalent header (app repo exposes this)
  #   2. Railway CLI deployment metadata (fallback / control-plane evidence)
  #
  # Usage:
  #   check_deploy_freshness [--endpoint-url URL] [-p PROJECT -e ENV -s SERVICE]
  #
  # Returns 0 if origin/master SHA matches live deployment, 1 otherwise.
  # Always outputs JSON.

  local endpoint_url=""
  local project_id=""
  local environment=""
  local service=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --endpoint-url) endpoint_url="$2"; shift 2 ;;
      -p|--project)    project_id="$2"; shift 2 ;;
      -e|--environment) environment="$2"; shift 2 ;;
      -s|--service)    service="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if ! command -v jq &>/dev/null; then
    echo '{"error": "jq required"}'
    return 1
  fi

  local expected_sha
  expected_sha=$(git rev-parse origin/master 2>/dev/null)
  if [[ -z "$expected_sha" ]]; then
    echo '{"error": "cannot resolve origin/master"}'
    return 1
  fi

  local actual_sha=""
  local source="none"

  # --- Source 1: Runtime endpoint (preferred) ---
  if [[ -n "$endpoint_url" ]]; then
    local commit_header
    commit_header=$(curl -sf -D - -o /dev/null "$endpoint_url" 2>/dev/null \
      | grep -i '^x-commit-sha:' \
      | head -1 \
      | sed 's/^[^:]*:[[:space:]]*//' \
      | tr -d '[:space:]')

    if [[ -n "$commit_header" && ${#commit_sha} -ge 7 ]]; then
      actual_sha="$commit_header"
      source="runtime_endpoint"
    fi
  fi

  # --- Source 2: Railway CLI deployment list (fallback) ---
  if [[ -z "$actual_sha" ]]; then
    local deploy_json
    local deploy_args=("--json" "--limit" "1")

    if [[ -n "$project_id" && -n "$environment" && -n "$service" ]]; then
      deploy_args+=("-p" "$project_id" "-e" "$environment" "-s" "$service")
    elif [[ -n "$service" ]]; then
      deploy_args+=("-s" "$service")
    fi

    deploy_json=$(railway deployment list "${deploy_args[@]}" 2>/dev/null || true)

    if [[ -n "$deploy_json" ]] && echo "$deploy_json" | jq -e . >/dev/null 2>&1; then
      actual_sha=$(echo "$deploy_json" | jq -r '.[0].commit  // empty' 2>/dev/null)
      if [[ -z "$actual_sha" ]]; then
        actual_sha=$(echo "$deploy_json" | jq -r '.[0].staticUrl // empty' 2>/dev/null | sed 's/.*-//')
      fi
      source="railway_cli"
    fi
  fi

  if [[ -z "$actual_sha" ]]; then
    echo "{\"expected_sha\": \"$expected_sha\", \"actual_sha\": null, \"source\": \"$source\", \"fresh\": false, \"drift\": true, \"error\": \"unable to determine live commit\"}"
    return 1
  fi

  local short_expected="${expected_sha:0:7}"
  local short_actual="${actual_sha:0:7}"

  if [[ "$short_expected" == "$short_actual" ]]; then
    echo "{\"expected_sha\": \"$expected_sha\", \"actual_sha\": \"$actual_sha\", \"source\": \"$source\", \"fresh\": true, \"drift\": false}"
    return 0
  else
    echo "{\"expected_sha\": \"$expected_sha\", \"actual_sha\": \"$actual_sha\", \"source\": \"$source\", \"fresh\": false, \"drift\": true}"
    return 1
  fi
}
