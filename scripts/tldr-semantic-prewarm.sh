#!/usr/bin/env bash
#
# tldr-semantic-prewarm.sh
#
# Proactively warms llm-tldr semantic indexes for canonical repos and/or
# active dx worktree paths to avoid cold-index latency in agent fallback flows.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL="all-MiniLM-L6-v2"
SINCE_HOURS=48
DRY_RUN=0
SCAN_CANONICAL=0
SCAN_ACTIVE_WORKTREES=0
EXPLICIT_PATH=""
HAD_SELECTED_FAILURE=0

LOCK_ROOT="${DX_STATE_DIR:-$HOME/.dx-state}/locks"

usage() {
  cat <<'EOF'
Usage:
  tldr-semantic-prewarm.sh [--path <path>] [--canonical] [--active-worktrees]
                           [--since-hours <N>] [--model <name>] [--dry-run]

Modes:
  --path <path>           Prewarm one explicit repo/worktree path
  --canonical             Scan canonical repos under $HOME
  --active-worktrees      Scan /tmp/agents/*/*
  --since-hours <N>       Active-worktree recency window in hours (default: 48)
  --model <name>          Embedding model for semantic index build
                          (default: all-MiniLM-L6-v2)
  --dry-run               Print what would happen without indexing
EOF
}

log_line() {
  local status="$1"
  shift
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" "$*"
}

resolve_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd -P)
    return 0
  fi
  printf '%s\n' "$path"
}

is_git_path() {
  local path="$1"
  git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

path_mtime_epoch() {
  local path="$1"
  if stat -f '%m' "$path" >/dev/null 2>&1; then
    stat -f '%m' "$path"
  elif stat -c '%Y' "$path" >/dev/null 2>&1; then
    stat -c '%Y' "$path"
  else
    printf '0\n'
  fi
}

llm_tldr_bin() {
  local candidate
  for candidate in \
    "${LLM_TLDR_BIN:-}" \
    "$(command -v llm-tldr 2>/dev/null || true)" \
    "$HOME/.local/bin/llm-tldr" \
    "/opt/homebrew/bin/llm-tldr" \
    "/usr/local/bin/llm-tldr"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

llm_tldr_python_bin() {
  local bin_path
  bin_path="$(llm_tldr_bin)" || return 1
  if [[ ! -f "$bin_path" ]]; then
    return 1
  fi
  head -n 1 "$bin_path" | sed 's/^#!//'
}

semantic_index_ready() {
  local project_path="$1"
  local pybin
  pybin="$(llm_tldr_python_bin)" || return 2
  "$pybin" - "$SCRIPT_DIR" "$project_path" <<'PY' >/dev/null 2>&1
import sys
script_dir = sys.argv[1]
project_path = sys.argv[2]
sys.path.insert(0, script_dir)
import tldr_contained_runtime as runtime
runtime.apply_containment_patches(include_mcp=False)
raise SystemExit(0 if runtime._semantic_index_ready(project_path) else 1)
PY
}

lock_key_for_path() {
  local project_path="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$project_path" | shasum | awk '{print $1}'
  elif command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$project_path" | sha1sum | awk '{print $1}'
  else
    printf '%s' "$project_path" | cksum | awk '{print $1 "-" $2}'
  fi
}

index_path() {
  local project_path="$1"
  local bin_path output=""
  bin_path="$(llm_tldr_bin)" || {
    log_line "FAIL" "path=$project_path reason=llm_tldr_missing"
    return 1
  }
  if output="$(LLM_TLDR_BIN="$bin_path" "$SCRIPT_DIR/tldr-contained.sh" semantic index "$project_path" --model "$MODEL" 2>&1)"; then
    log_line "WARM" "path=$project_path model=$MODEL"
    return 0
  fi
  log_line "FAIL" "path=$project_path reason=index_failed model=$MODEL detail=$(printf '%s' "$output" | tail -n 1)"
  return 1
}

warm_path_with_lock() {
  local project_path="$1"
  local key lock_file lock_dir rc
  mkdir -p "$LOCK_ROOT"
  key="$(lock_key_for_path "$project_path")"
  lock_file="$LOCK_ROOT/tldr-semantic-prewarm-$key.lock"

  if command -v flock >/dev/null 2>&1; then
    set +e
    (
      flock -n 9 || exit 42
      if semantic_index_ready "$project_path"; then
        log_line "SKIP_READY" "path=$project_path"
        exit 0
      fi
      index_path "$project_path"
    ) 9>"$lock_file"
    rc="$?"
    set -e
    case "$rc" in
      0) return 0 ;;
      42)
        log_line "SKIP_LOCKED" "path=$project_path lock=$lock_file"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  lock_dir="${lock_file}.d"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    log_line "SKIP_LOCKED" "path=$project_path lock=$lock_dir"
    return 0
  fi
  rc=0
  if semantic_index_ready "$project_path"; then
    log_line "SKIP_READY" "path=$project_path"
  elif ! index_path "$project_path"; then
    rc=1
  fi
  rmdir "$lock_dir" >/dev/null 2>&1 || true
  return "$rc"
}

TARGETS_NL=""

add_target() {
  local candidate="$1"
  if [[ -z "$candidate" ]]; then
    return 0
  fi
  candidate="$(resolve_path "$candidate")"
  if printf '%s' "$TARGETS_NL" | grep -F -x -- "$candidate" >/dev/null 2>&1; then
    return 0
  fi
  TARGETS_NL+="$candidate"$'\n'
}

collect_canonical_targets() {
  local repo path
  for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    path="$HOME/$repo"
    if [[ -d "$path" ]]; then
      add_target "$path"
    fi
  done
}

collect_active_worktree_targets() {
  local now cutoff path mtime
  if [[ ! "$SINCE_HOURS" =~ ^[0-9]+$ ]]; then
    log_line "FAIL" "reason=invalid_since_hours value=$SINCE_HOURS"
    HAD_SELECTED_FAILURE=1
    return 0
  fi
  now="$(date +%s)"
  cutoff=$((now - (SINCE_HOURS * 3600)))
  while IFS= read -r path; do
    [[ -n "$path" && -d "$path" && -e "$path/.git" ]] || continue
    mtime="$(path_mtime_epoch "$path")"
    [[ "$mtime" -ge "$cutoff" ]] || continue
    add_target "$path"
  done < <(find /tmp/agents -mindepth 2 -maxdepth 2 -type d 2>/dev/null || true)
}

process_target() {
  local target="$1"
  local explicit_mode="$2"

  if [[ ! -d "$target" ]]; then
    log_line "SKIP_MISSING" "path=$target"
    [[ "$explicit_mode" == "1" ]] && return 1
    return 0
  fi

  if ! is_git_path "$target"; then
    log_line "SKIP_NOT_GIT" "path=$target"
    [[ "$explicit_mode" == "1" ]] && return 1
    return 0
  fi

  if semantic_index_ready "$target"; then
    log_line "SKIP_READY" "path=$target"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log_line "WARM" "path=$target model=$MODEL dry_run=1"
    return 0
  fi

  if ! warm_path_with_lock "$target"; then
    return 1
  fi
  return 0
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --path)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      EXPLICIT_PATH="$2"
      shift 2
      ;;
    --canonical)
      SCAN_CANONICAL=1
      shift
      ;;
    --active-worktrees)
      SCAN_ACTIVE_WORKTREES=1
      shift
      ;;
    --since-hours)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      SINCE_HOURS="$2"
      shift 2
      ;;
    --model)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      MODEL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$EXPLICIT_PATH" ]]; then
  add_target "$EXPLICIT_PATH"
fi

if [[ "$SCAN_CANONICAL" == "1" ]]; then
  collect_canonical_targets
fi

if [[ "$SCAN_ACTIVE_WORKTREES" == "1" ]]; then
  collect_active_worktree_targets
fi

if [[ -z "$TARGETS_NL" ]]; then
  usage >&2
  exit 2
fi

while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  if ! process_target "$target" "$([[ -n "$EXPLICIT_PATH" && "$target" == "$(resolve_path "$EXPLICIT_PATH")" ]] && echo 1 || echo 0)"; then
    HAD_SELECTED_FAILURE=1
  fi
done <<<"$TARGETS_NL"

exit "$HAD_SELECTED_FAILURE"
