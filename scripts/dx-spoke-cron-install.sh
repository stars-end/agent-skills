#!/usr/bin/env bash
#
# dx-spoke-cron-install.sh
#
# Installs non-controller DX cron jobs that should exist on ordinary canonical
# development hosts. This supplements the V8 cleanup schedule installed by
# dx-hydrate.sh and intentionally avoids controller-only jobs.

set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-$HOME/agent-skills}"
WRAPPER="$AGENTS_ROOT/scripts/dx-job-wrapper.sh"

if [[ -x /opt/homebrew/bin/bash ]]; then
  BASH_PATH="/opt/homebrew/bin/bash"
elif [[ -x /usr/bin/bash ]]; then
  BASH_PATH="/usr/bin/bash"
else
  BASH_PATH="/bin/bash"
fi

mkdir -p "$HOME/logs/dx"

install_crontab_from_stdin() {
  local tmp_cron
  local pid waited rc
  tmp_cron="$(mktemp)"
  cat >"$tmp_cron"
  crontab "$tmp_cron" &
  pid="$!"
  waited=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    if [[ "$waited" -ge "${DX_CRONTAB_INSTALL_TIMEOUT_SECONDS:-10}" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      rm -f "$tmp_cron"
      printf 'ERROR: crontab install hung after %ss; leaving crontab unchanged\n' "${DX_CRONTAB_INSTALL_TIMEOUT_SECONDS:-10}" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  set +e
  wait "$pid"
  rc="$?"
  set -e
  rm -f "$tmp_cron"
  return "$rc"
}

host_key() {
  local short_host
  short_host="$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"

  case "$short_host" in
    epyc12|*epyc12*|v2202601262171429561*) printf 'epyc12\n' ;;
    *) printf 'spoke\n' ;;
  esac
}

install_cron_entry() {
  local marker="$1"
  local entry="$2"
  local current_cron updated_cron

  current_cron="$(crontab -l 2>/dev/null || true)"

  if printf '%s\n' "$current_cron" | grep -qF "# $marker"; then
    if printf '%s\n' "$current_cron" | grep -qF "$entry"; then
      printf 'Cron already installed: %s\n' "$marker"
      return 0
    fi

    updated_cron="$(
      printf '%s\n' "$current_cron" | awk -v marker="$marker" '
        BEGIN { skip_next=0 }
        skip_next { skip_next=0; next }
        $0 == "# " marker { skip_next=1; next }
        { print }
      '
    )"
    {
      printf '%s\n' "$updated_cron"
      printf '\n# %s\n%s\n' "$marker" "$entry"
    } | install_crontab_from_stdin
    printf 'Updated cron: %s\n' "$marker"
    return 0
  fi

  {
    printf '%s\n' "$current_cron"
    printf '\n# %s\n%s\n' "$marker" "$entry"
  } | install_crontab_from_stdin
  printf 'Added cron: %s\n' "$marker"
}

remove_wrapper_job_entries() {
  local job_name="$1"
  local script_name="$2"
  local current_cron updated_cron

  current_cron="$(crontab -l 2>/dev/null || true)"
  updated_cron="$(
    printf '%s\n' "$current_cron" | awk -v job="$job_name" -v script="$script_name" '
      /^[[:space:]]*#/ { print; next }
      /^[[:space:]]*$/ { print; next }
      {
        if (index($0, "dx-job-wrapper.sh") > 0 &&
            index($0, " " job " -- ") > 0 &&
            index($0, script) > 0) {
          next
        }
        print
      }
    '
  )"

  if [[ "$updated_cron" != "$current_cron" ]]; then
    printf '%s\n' "$updated_cron" | install_crontab_from_stdin
    printf 'Pruned duplicate cron entries for: %s (%s)\n' "$job_name" "$script_name"
  fi
}

install_fetch_jobs() {
  remove_wrapper_job_entries "fetch-agent-skills" "canonical-fetch.sh"
  remove_wrapper_job_entries "fetch-prime" "canonical-fetch.sh"
  remove_wrapper_job_entries "fetch-affordabot" "canonical-fetch.sh"
  remove_wrapper_job_entries "fetch-llm" "canonical-fetch.sh"
  remove_wrapper_job_entries "reconcile" "canonical-reconcile.sh"

  install_cron_entry "DX spoke: fetch-agent-skills" \
    "5,35 * * * * $BASH_PATH $WRAPPER fetch-agent-skills -- $AGENTS_ROOT/scripts/canonical-fetch.sh agent-skills >> $HOME/logs/dx/fetch-agent-skills.log 2>&1"
  install_cron_entry "DX spoke: fetch-prime" \
    "10,40 * * * * $BASH_PATH $WRAPPER fetch-prime -- $AGENTS_ROOT/scripts/canonical-fetch.sh prime-radiant-ai >> $HOME/logs/dx/fetch-prime.log 2>&1"
  install_cron_entry "DX spoke: fetch-affordabot" \
    "15,45 * * * * $BASH_PATH $WRAPPER fetch-affordabot -- $AGENTS_ROOT/scripts/canonical-fetch.sh affordabot >> $HOME/logs/dx/fetch-affordabot.log 2>&1"
  install_cron_entry "DX spoke: fetch-llm" \
    "20,50 * * * * $BASH_PATH $WRAPPER fetch-llm -- $AGENTS_ROOT/scripts/canonical-fetch.sh llm-common >> $HOME/logs/dx/fetch-llm.log 2>&1"
  install_cron_entry "DX spoke: reconcile" \
    "0 */2 * * * $BASH_PATH $WRAPPER reconcile -- $AGENTS_ROOT/scripts/canonical-reconcile.sh >> $HOME/logs/dx/reconcile.log 2>&1"
}

install_cache_sync_job() {
  if [[ "$(host_key)" == "epyc12" ]]; then
    printf 'Skipping OP cache sync on epyc12 cache source host\n'
    return 0
  fi

  remove_wrapper_job_entries "sync-op-cache" "dx-sync-op-caches.sh"
  install_cron_entry "DX spoke: sync-op-cache" \
    "2,17,32,47 * * * * $BASH_PATH $WRAPPER sync-op-cache -- $AGENTS_ROOT/scripts/dx-sync-op-caches.sh >> $HOME/logs/dx/sync-op-cache.log 2>&1"
}

main() {
  install_fetch_jobs
  install_cache_sync_job
}

main "$@"
