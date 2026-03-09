#!/usr/bin/env bash
set -euo pipefail

#
# skills-doctor check.sh
#
# Validates the shared skills plane at ~/.agent/skills and repo-specific skill requirements.
#
# Usage:
#   check.sh              - Human-readable output
#   check.sh --json       - JSON output for fleet integration
#
# Checks performed:
#   1. Skills-plane existence and symlink integrity
#   2. Canonical files (AGENTS.md, dist/universal-baseline.md)
#   3. Required skill directories for repo profile
#   4. Optional: installed SHA reporting
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agent/skills}"
PROFILE="${SKILLS_DOCTOR_PROFILE:-}"
OUTPUT_FORMAT="text"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_FORMAT="json" ; shift ;;
    *) shift ;;
  esac
done

# JSON helper functions
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Collect check results
declare -a CHECKS=()
declare -a DETAILS=()
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

add_check() {
  local id="$1" status="$2" detail="$3"
  CHECKS+=("$id:$status")
  DETAILS+=("$detail")
  case "$status" in
    pass) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    fail) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    warn) WARN_COUNT=$((WARN_COUNT + 1)) ;;
  esac
}

# ------------------------------------------------------------
# 1. Skills-Plane Existence Check
# ------------------------------------------------------------
check_skills_plane_exists() {
  local id="skills_plane_exists"
  if [[ ! -e "$SKILLS_DIR" ]]; then
    add_check "$id" "fail" "Skills directory does not exist: $SKILLS_DIR"
    return 1
  fi
  add_check "$id" "pass" "Skills directory exists: $SKILLS_DIR"
  return 0
}

# ------------------------------------------------------------
# 2. Symlink Integrity Check
# ------------------------------------------------------------
check_skills_symlink() {
  local id="skills_symlink_integrity"
  local link_target

  if [[ -L "$SKILLS_DIR" ]]; then
    link_target="$(readlink -f "$SKILLS_DIR" 2>/dev/null || readlink "$SKILLS_DIR")"
    if [[ "$link_target" == *"agent-skills"* ]]; then
      add_check "$id" "pass" "Symlink points to canonical agent-skills: $link_target"
      return 0
    else
      add_check "$id" "warn" "Symlink points to non-canonical location: $link_target"
      return 0
    fi
  elif [[ -d "$SKILLS_DIR" ]]; then
    # Not a symlink but a directory - check if it's a git checkout
    if [[ -d "$SKILLS_DIR/.git" ]]; then
      add_check "$id" "pass" "Skills directory is a git checkout (not symlinked)"
      return 0
    fi
    add_check "$id" "warn" "Skills directory is neither symlink nor git checkout"
    return 0
  fi

  add_check "$id" "fail" "Skills directory is neither symlink nor directory"
  return 1
}

# ------------------------------------------------------------
# 3. Canonical Files Check
# ------------------------------------------------------------
check_canonical_files() {
  local id="canonical_files_present"
  local missing=()

  [[ -f "$SKILLS_DIR/AGENTS.md" ]] || missing+=("AGENTS.md")
  [[ -f "$SKILLS_DIR/dist/universal-baseline.md" ]] || missing+=("dist/universal-baseline.md")

  if [[ ${#missing[@]} -eq 0 ]]; then
    add_check "$id" "pass" "Canonical files present"
    return 0
  fi
  add_check "$id" "fail" "Missing canonical files: ${missing[*]}"
  return 1
}

# ------------------------------------------------------------
# 4. Required Skill Directories Check
# ------------------------------------------------------------
detect_repo_profile() {
  local repo_root remote_url

  if [[ -n "$PROFILE" ]]; then
    echo "$PROFILE"
    return 0
  fi

  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  remote_url="$(git -C "$repo_root" remote get-url origin 2>/dev/null || true)"

  case "$remote_url" in
    *stars-end/prime-radiant-ai*|*stars-end/prime-radiant-ai.git*)
      echo "prime-radiant-ai"
      ;;
    *stars-end/affordabot*|*stars-end/affordabot.git*)
      echo "affordabot"
      ;;
    *stars-end/llm-common*|*stars-end/llm-common.git*)
      echo "llm-common"
      ;;
    *stars-end/agent-skills*|*stars-end/agent-skills.git*)
      echo "agent-skills"
      ;;
    *)
      echo "$(basename "$repo_root")"
      ;;
  esac
}

check_required_skills() {
  local profile="$1"
  local profiles_dir="$SCRIPT_DIR/../../skill-profiles"
  local profile_file="$profiles_dir/${profile}.json"
  local missing=()
  local req_skills

  if [[ ! -f "$profile_file" ]]; then
    add_check "required_skills_$profile" "warn" "No profile found for: $profile"
    return 0
  fi

  # Extract required skills from profile
  req_skills=$(python3 - "$profile_file" <<'PY'
import json,sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
  data = json.load(f)
skills = data.get("required", [])
skills = [s for s in skills if isinstance(s, str) and s.strip()]
print("\n".join(dict.fromkeys(skills)))
PY
)

  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    if [[ ! -d "$SKILLS_DIR/$skill" ]]; then
      missing+=("$skill")
    fi
  done <<< "$req_skills"

  if [[ ${#missing[@]} -eq 0 ]]; then
    add_check "required_skills_$profile" "pass" "All required skills present for $profile"
    return 0
  fi
  add_check "required_skills_$profile" "fail" "Missing required skills: ${missing[*]}"
  return 1
}

# ------------------------------------------------------------
# 5. Installed SHA Check (optional, informational)
# ------------------------------------------------------------
check_installed_sha() {
  local id="installed_sha"
  local sha

  if [[ -d "$SKILLS_DIR/.git" ]]; then
    sha="$(git -C "$SKILLS_DIR" rev-parse --short HEAD 2>/dev/null || true)"
    if [[ -n "$sha" ]]; then
      add_check "$id" "pass" "Installed SHA: $sha"
      return 0
    fi
  fi
  add_check "$id" "warn" "Could not determine installed SHA"
  return 0
}

# ------------------------------------------------------------
# Main execution
# ------------------------------------------------------------
main() {
  check_skills_plane_exists
  check_skills_symlink
  check_canonical_files

  local profile
  profile="$(detect_repo_profile)"
  check_required_skills "$profile"
  check_installed_sha

  # Compute overall status
  local overall="green"
  if [[ $FAIL_COUNT -gt 0 ]]; then
    overall="red"
  elif [[ $WARN_COUNT -gt 0 ]]; then
    overall="yellow"
  fi

  # Output
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    local checks_json="["
    local first=1
    for i in "${!CHECKS[@]}"; do
      local check="${CHECKS[$i]}"
      local detail="${DETAILS[$i]}"
      local id="${check%%:*}"
      local status="${check##*:}"

      if [[ $first -eq 1 ]]; then
        first=0
      else
        checks_json+=","
      fi
      checks_json+="{\"id\":\"$(json_escape "$id")\",\"status\":\"$(json_escape "$status")\",\"details\":\"$(json_escape "$detail")\"}"
    done
    checks_json+="]"

    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    printf '{"generated_at":"%s","overall":"%s","summary":{"pass":%d,"warn":%d,"fail":%d},"profile":"%s","skills_dir":"%s","checks":%s}\n' \
      "$timestamp" "$overall" "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT" "$profile" "$SKILLS_DIR" "$checks_json"
  else
    echo "🔎 skills-doctor - checking skills plane and repo requirements"
    echo ""

    for i in "${!CHECKS[@]}"; do
      local check="${CHECKS[$i]}"
      local detail="${DETAILS[$i]}"
      local status="${check##*:}"
      local icon

      case "$status" in
        pass) icon="✅" ;;
        fail) icon="❌" ;;
        warn) icon="⚠️" ;;
        *) icon="❓" ;;
      esac
      echo "$icon $detail"
    done

    echo ""
    if [[ "$overall" == "green" ]]; then
      echo "✅ skills-doctor: all checks passed ($PROFILE)"
      exit 0
    elif [[ "$overall" == "yellow" ]]; then
      echo "⚠️ skills-doctor: warnings detected"
      exit 2
    else
      echo "❌ skills-doctor: failures detected"
      echo ""
      echo "Fix:"
      echo "  cd \"$SKILLS_DIR\" && git pull"
      exit 1
    fi
  fi
}

main
