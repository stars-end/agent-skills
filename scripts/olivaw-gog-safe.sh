#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_DEFAULT="fengning@stars-end.ai"
CLIENT_DEFAULT="olivaw-gog"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <gog-subcommand> [args...]" >&2
  exit 2
fi

if ! command -v gog >/dev/null 2>&1; then
  echo "blocked: gog binary not found" >&2
  exit 127
fi

family="$1"
command_name="${2:-}"

allow_read_command() {
  local family="$1"
  local command_name="$2"

  case "${family}:${command_name}" in
    auth:doctor)
      return 0
      ;;
    gmail:search)
      return 0
      ;;
    calendar:calendars|calendar:events|calendar:list|calendar:ls|calendar:search|calendar:freebusy|calendar:colors|calendar:conflicts|calendar:time|calendar:users)
      return 0
      ;;
    drive:ls|drive:search|drive:tree|drive:du|drive:inventory|drive:get|drive:raw|drive:drives|drive:url)
      return 0
      ;;
    docs:info|docs:get|docs:show|docs:cat|docs:text|docs:read|docs:export|docs:download|docs:dl|docs:structure|docs:struct|docs:raw|docs:list-tabs)
      return 0
      ;;
    sheets:get|sheets:read|sheets:show|sheets:metadata|sheets:info|sheets:export|sheets:download|sheets:dl|sheets:notes|sheets:links|sheets:hyperlinks|sheets:raw)
      return 0
      ;;
    contacts:list|contacts:ls|contacts:search|contacts:get|contacts:info|contacts:show|contacts:dedupe|contacts:raw)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if ! allow_read_command "${family}" "${command_name}"; then
  echo "blocked: olivaw gog policy allows only approved read/doctor commands; got '${family} ${command_name}'" >&2
  exit 10
fi

export GOG_ACCOUNT="${ACCOUNT_DEFAULT}"
exec gog --client "${CLIENT_DEFAULT}" --gmail-no-send "$@"
