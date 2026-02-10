#!/usr/bin/env bash
# dx-triage.sh
# Repo state diagnosis + (optional) safe recovery + triage artifacts for pre-push gating.
#
# This script writes worktree-safe triage artifacts into each repo's *git common dir*:
#   DX_TRIAGE_STATUS    (always written)
#   DX_TRIAGE_REQUIRED  (only for critical issues: dirty canonical, non-trunk canonical, missing repo)
#   DX_TRIAGE_ACK       (written by --ack / --fix)
#
# Usage:
#   dx-triage              # Show state for all canonical repos and write DX_TRIAGE_STATUS
#   dx-triage --fix        # Apply safe fixes (ff-only pull on stale trunk; reset merged feature branches)
#   dx-triage --ack        # Record acknowledgment for current DX_TRIAGE_STATUS fingerprint(s)
#
set -euo pipefail

# Ensure bash >= 4 for associative arrays (macOS may default to bash 3.2).
if [[ -n "${BASH_VERSINFO:-}" ]] && [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$candidate" ]]; then
      exec "$candidate" "$0" "$@"
    fi
  done
  echo "dx-triage requires bash >= 4 (install via Homebrew: brew install bash)" >&2
  exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

MODE="status"
case "${1:-}" in
  --fix) MODE="fix" ;;
  --ack) MODE="ack" ;;
  --help|-h)
    cat <<'EOF'
dx-triage - Repo state diagnosis and safe recovery

Usage:
  dx-triage              Show current state of all canonical repos (and write DX_TRIAGE_STATUS)
  dx-triage --fix        Apply safe fixes (ff-only pull; reset merged feature branches)
  dx-triage --ack        Acknowledge current status fingerprint(s) so pre-push can proceed
  dx-triage --help       Show this help

Notes:
  - Worktree-safe: artifacts are written to the git *common* dir.
  - Pre-push gating reads:
      DX_TRIAGE_STATUS + DX_TRIAGE_ACK (fingerprint match)
      DX_TRIAGE_REQUIRED (always blocks)
  - Non-interactive ack: set DX_TRIAGE_ACK_CONFIRM=yes
EOF
    exit 0
    ;;
esac

# Resolve symlinks to get actual script directory.
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

CANONICAL_TRUNK_BRANCH="${CANONICAL_TRUNK_BRANCH:-master}"
STATUS_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Collect all repos to check (required + optional; fallback to CANONICAL_REPOS).
ALL_REPOS=()
if declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1; then
  ALL_REPOS+=("${CANONICAL_REQUIRED_REPOS[@]}")
fi
if declare -p CANONICAL_OPTIONAL_REPOS >/dev/null 2>&1; then
  ALL_REPOS+=("${CANONICAL_OPTIONAL_REPOS[@]}")
fi
if [[ ${#ALL_REPOS[@]} -eq 0 ]] && declare -p CANONICAL_REPOS >/dev/null 2>&1; then
  ALL_REPOS+=("${CANONICAL_REPOS[@]}")
fi
if [[ ${#ALL_REPOS[@]} -eq 0 ]]; then
  echo -e "${RED}Error: No canonical repos defined (expected canonical-targets.sh)${RESET}" >&2
  exit 1
fi

declare -A REPO_STATE
declare -A REPO_BRANCH
declare -A REPO_BEHIND
declare -A REPO_DIRTY
declare -A REPO_EXISTS
declare -A REPO_FINGERPRINT
declare -A REPO_COMMON_DIR

abs_path() {
  python3 - <<'PY' "$1"
import os,sys
print(os.path.abspath(sys.argv[1]))
PY
}

git_common_dir_for_repo() {
  local repo_path="$1"
  local common_dir
  common_dir="$(git -C "$repo_path" rev-parse --git-common-dir 2>/dev/null || echo ".git")"
  if [[ "$common_dir" != /* ]]; then
    common_dir="$repo_path/$common_dir"
  fi
  abs_path "$common_dir"
}

write_status_files() {
  local repo="$1"
  local repo_path="$2"

  local common_dir="${REPO_COMMON_DIR[$repo]}"
  local status_file="$common_dir/DX_TRIAGE_STATUS"
  local required_file="$common_dir/DX_TRIAGE_REQUIRED"

  local state="${REPO_STATE[$repo]}"
  local branch="${REPO_BRANCH[$repo]:-unknown}"
  local dirty="${REPO_DIRTY[$repo]:-0}"
  local behind="${REPO_BEHIND[$repo]:-0}"
  local fp="${REPO_FINGERPRINT[$repo]}"

  mkdir -p "$common_dir" >/dev/null 2>&1 || true

  {
    echo "STATUS_AT: $STATUS_AT"
    echo "X_FINGERPRINT: $fp"
    echo "BRANCH: $branch"
    echo "STATE: $state"
    echo "DIRTY: $dirty uncommitted files"
    echo "BEHIND: $behind commits behind origin/$CANONICAL_TRUNK_BRANCH"
    echo ""
    echo "Current issues:"
    case "$state" in
      OK) echo "  None" ;;
      STALE) echo "  - Behind origin/$CANONICAL_TRUNK_BRANCH ($behind)" ;;
      DIRTY) echo "  - Uncommitted changes ($dirty)" ;;
      FEATURE) echo "  - Canonical clone is not on trunk ($CANONICAL_TRUNK_BRANCH)" ;;
      MISSING) echo "  - Repo missing at $repo_path" ;;
      *) echo "  - $state" ;;
    esac
  } > "$status_file"

  # Critical flags: canonical missing, dirty, or not on trunk.
  if [[ "$state" == "MISSING" || "$state" == "DIRTY" || "$state" == "FEATURE" ]]; then
    {
      echo "STATUS_AT: $STATUS_AT"
      echo "X_FINGERPRINT: $fp"
      echo "REPO: $repo"
      echo "CRITICAL: manual review required"
      echo ""
      echo "Reason:"
      if [[ "$state" == "MISSING" ]]; then
        echo "  - Repo missing: $repo_path"
      fi
      if [[ "$state" == "DIRTY" ]]; then
        echo "  - Uncommitted changes in canonical clone ($dirty)"
      fi
      if [[ "$state" == "FEATURE" ]]; then
        echo "  - Canonical clone is on feature branch: $branch (expected: $CANONICAL_TRUNK_BRANCH)"
      fi
      echo ""
      echo "Fix:"
      echo "  - Move WIP to a worktree (/tmp/agents/...) or stash/commit."
      echo "  - Reset canonical clone to trunk ($CANONICAL_TRUNK_BRANCH)."
    } > "$required_file"
  else
    rm -f "$required_file" >/dev/null 2>&1 || true
  fi
}

write_ack_files() {
  local repo="$1"
  local common_dir="${REPO_COMMON_DIR[$repo]}"
  local ack_file="$common_dir/DX_TRIAGE_ACK"
  local fp="${REPO_FINGERPRINT[$repo]}"
  {
    echo "ACKED_AT: $STATUS_AT"
    echo "X_FINGERPRINT: $fp"
  } > "$ack_file"
}

echo -e "${BLUE}=== dx-triage ($(hostname -s 2>/dev/null || hostname)) ===${RESET}"
echo ""
echo -e "${CYAN}Surveying repos...${RESET}"

for repo in "${ALL_REPOS[@]}"; do
  repo_path="$HOME/$repo"
  REPO_COMMON_DIR[$repo]="$repo_path/.git"

  if [[ ! -d "$repo_path/.git" ]]; then
    REPO_EXISTS[$repo]=0
    REPO_STATE[$repo]="MISSING"
    REPO_BRANCH[$repo]="n/a"
    REPO_DIRTY[$repo]=0
    REPO_BEHIND[$repo]=0
    REPO_COMMON_DIR[$repo]="$repo_path/.git"
    REPO_FINGERPRINT[$repo]="BRANCH:n/a|STATE:MISSING|DIRTY:0|BEHIND:0|ISSUES:1"
    # No git-common-dir available; write required/status next to expected path (best-effort).
    mkdir -p "$repo_path" >/dev/null 2>&1 || true
    REPO_COMMON_DIR[$repo]="$(abs_path "$repo_path/.git")"
    write_status_files "$repo" "$repo_path"
    continue
  fi

  REPO_EXISTS[$repo]=1
  REPO_COMMON_DIR[$repo]="$(git_common_dir_for_repo "$repo_path")"

  git -C "$repo_path" fetch origin --quiet 2>/dev/null || true

  branch="$(git -C "$repo_path" branch --show-current 2>/dev/null || git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
  REPO_BRANCH[$repo]="$branch"

  dirty_count="$(git -C "$repo_path" status --porcelain=v1 2>/dev/null | wc -l | tr -d ' ')"
  REPO_DIRTY[$repo]="$dirty_count"

  behind=0
  if git -C "$repo_path" rev-parse --verify "origin/$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1; then
    behind="$(git -C "$repo_path" rev-list --count "HEAD..origin/$CANONICAL_TRUNK_BRANCH" 2>/dev/null || echo 0)"
  fi
  REPO_BEHIND[$repo]="$behind"

  issues=0
  state="OK"

  if [[ "$branch" != "$CANONICAL_TRUNK_BRANCH" ]]; then
    state="FEATURE"
    issues=$((issues + 1))
  fi
  if [[ "$dirty_count" -gt 0 ]]; then
    state="DIRTY"
    issues=$((issues + 1))
  fi
  if [[ "$branch" == "$CANONICAL_TRUNK_BRANCH" && "$dirty_count" -eq 0 && "$behind" -gt 0 ]]; then
    state="STALE"
    issues=$((issues + 1))
  fi

  REPO_STATE[$repo]="$state"
  REPO_FINGERPRINT[$repo]="BRANCH:${branch}|STATE:${state}|DIRTY:${dirty_count}|BEHIND:${behind}|ISSUES:${issues}"

  write_status_files "$repo" "$repo_path"
done

echo ""
printf "%-18s %-10s %-24s %-8s %s\n" "REPO" "STATE" "BRANCH" "DIRTY" "DETAILS"
printf "%-18s %-10s %-24s %-8s %s\n" "----" "-----" "------" "-----" "-------"

safe_fixes=0
manual_needed=0

for repo in "${ALL_REPOS[@]}"; do
  state="${REPO_STATE[$repo]}"
  branch="${REPO_BRANCH[$repo]:-n/a}"
  dirty="${REPO_DIRTY[$repo]:-0}"
  behind="${REPO_BEHIND[$repo]:-0}"

  case "$state" in
    OK) state_color="${GREEN}OK${RESET}" ;;
    STALE) state_color="${YELLOW}STALE${RESET}" ;;
    DIRTY) state_color="${RED}DIRTY${RESET}" ;;
    FEATURE) state_color="${YELLOW}FEATURE${RESET}" ;;
    MISSING) state_color="${RED}MISSING${RESET}" ;;
    *) state_color="$state" ;;
  esac

  details=""
  [[ "$behind" -gt 0 ]] && details+="↓${behind} "
  [[ "$dirty" -gt 0 ]] && details+="${dirty} uncommitted "

  if [[ ${#branch} -gt 22 ]]; then
    branch="${branch:0:19}..."
  fi

  printf "%-18s %-20b %-24s %-8s %s\n" "$repo" "$state_color" "$branch" "$dirty" "$details"

  case "$state" in
    STALE|OK) ;;
    *) manual_needed=$((manual_needed + 1)) ;;
  esac
  if [[ "$state" == "STALE" ]]; then
    safe_fixes=$((safe_fixes + 1))
  fi
done

echo ""
echo -e "${CYAN}Recommendations:${RESET}"
for repo in "${ALL_REPOS[@]}"; do
  state="${REPO_STATE[$repo]}"
  behind="${REPO_BEHIND[$repo]:-0}"
  case "$state" in
    OK) ;;
    STALE) echo -e "  ${GREEN}✓${RESET} $repo: git pull --ff-only (safe) (${behind} behind)" ;;
    DIRTY) echo -e "  ${RED}!${RESET} $repo: canonical clone dirty - move WIP to a worktree; reset canonical" ;;
    FEATURE) echo -e "  ${YELLOW}?${RESET} $repo: canonical clone not on trunk ($CANONICAL_TRUNK_BRANCH)" ;;
    MISSING) echo -e "  ${RED}!${RESET} $repo: missing at ~/$repo (clone required)" ;;
  esac
done
echo ""

if [[ "$MODE" == "fix" ]]; then
  echo -e "${BLUE}Applying safe fixes...${RESET}"
  for repo in "${ALL_REPOS[@]}"; do
    repo_path="$HOME/$repo"
    [[ -d "$repo_path/.git" ]] || continue
    state="${REPO_STATE[$repo]}"
    if [[ "$state" == "STALE" ]]; then
      echo -n "  $repo: pulling... "
      if git -C "$repo_path" pull --ff-only origin "$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1; then
        echo -e "${GREEN}done${RESET}"
      else
        echo -e "${RED}failed${RESET}"
      fi
    fi
  done

  # Refresh status + ACK after fixes.
  for repo in "${ALL_REPOS[@]}"; do
    [[ "${REPO_EXISTS[$repo]:-0}" -eq 1 ]] || continue
    write_ack_files "$repo"
  done
  echo ""
  echo -e "${GREEN}Safe fixes applied and acknowledged.${RESET}"
  exit 0
fi

if [[ "$MODE" == "ack" ]]; then
  if [[ "${DX_TRIAGE_ACK_CONFIRM:-}" != "yes" ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Type 'yes' to confirm: " confirm
      if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        exit 1
      fi
    else
      echo "Non-interactive mode. Set DX_TRIAGE_ACK_CONFIRM=yes to proceed." >&2
      exit 1
    fi
  fi

  for repo in "${ALL_REPOS[@]}"; do
    [[ "${REPO_EXISTS[$repo]:-0}" -eq 1 ]] || continue
    # Clear critical flags; record ACK fingerprint.
    rm -f "${REPO_COMMON_DIR[$repo]}/DX_TRIAGE_REQUIRED" >/dev/null 2>&1 || true
    write_ack_files "$repo"
  done
  echo -e "${GREEN}Acknowledged. Pre-push fingerprint check should pass now.${RESET}"
  exit 0
fi

exit 0

