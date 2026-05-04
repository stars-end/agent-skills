#!/usr/bin/env bash
#
# dx-codex-session-repair-cron-install.sh
#
# Install/update the nightly Codex session repair cron on the current host.
#
set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-$HOME/agent-skills}"
WRAPPER="$AGENTS_ROOT/scripts/dx-job-wrapper.sh"
REPAIR_WRAPPER="$AGENTS_ROOT/scripts/dx-codex-session-repair.sh"

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
    v2202601262171429561*|epyc12|*epyc12*) printf 'epyc12\n' ;;
    v2202509262171386004*|epyc6|*epyc6*) printf 'epyc6\n' ;;
    fengs-mac-mini-3*|macmini|*macmini*) printf 'macmini\n' ;;
    *) printf 'unsupported\n' ;;
  esac
}

schedule_for_host() {
  case "$(host_key)" in
    macmini) printf '12 3 * * *\n' ;;
    epyc12) printf '27 3 * * *\n' ;;
    epyc6) printf '42 3 * * *\n' ;;
    *) return 1 ;;
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

main() {
  local schedule marker entry
  schedule="$(schedule_for_host)" || {
    echo "Host not in Codex session repair rollout set; skipping"
    return 0
  }
  marker="DX nightly: codex-session-repair"
  entry="$schedule $BASH_PATH $WRAPPER codex-session-repair -- $REPAIR_WRAPPER --repair --json >> $HOME/logs/dx/codex-session-repair-cron.log 2>&1"
  install_cron_entry "$marker" "$entry"
}

main "$@"
