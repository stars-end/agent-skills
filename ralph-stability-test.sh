#!/bin/bash
set -e

BASE="http://localhost:4105"
WORKSPACE="$(pwd)"
TEST_DIR="/tmp/ralph-stability-test-$$"
mkdir -p "$TEST_DIR/logs"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo "[$(date '+%H:%M:%S')] $@" | tee -a "$TEST_DIR/logs/test.log"; }
info() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $@${NC}" | tee -a "$TEST_DIR/logs/test.log"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] $@${NC}" | tee -a "$TEST_DIR/logs/test.log"; }
header() { echo -e "${CYAN}═════════════════════════════════════════════════════════════════${NC}" | tee -a "$TEST_DIR/logs/test.log"; echo -e "${CYAN} $@${NC}" | tee -a "$TEST_DIR/logs/test.log"; echo -e "${CYAN}═════════════════════════════════════════════════════════════════${NC}" | tee -a "$TEST_DIR/logs/test.log"; }

# Statistics
STATS_FILE="$TEST_DIR/stats.json"
echo '{"cycles":0,"approvals":0,"revisions":0,"failures":0,"signals":[],"sessions":[]}' > "$STATS_FILE"

get_next_criterion() {
  grep '\[ \]' "$WORKSPACE/RALPH_TASK.md" | head -1
}

mark_complete() {
  local criterion="$1"
  perl -i -pe 's/\[ \] '"$(printf '%s' "$criterion" | sed 's/[]\/$*.^[]/\\$&g/')"'/[x]/' "$WORKSPACE/RALPH_TASK.md"
}

parse_reviewer_output() {
  local output="$1"
  if echo "$output" | grep -q "✅ APPROVED"; then
    echo "APPROVED"
  elif echo "$output" | grep -q "🔴 REVISION_REQUIRED"; then
    echo "REVISION_REQUIRED"
  else
    echo "UNKNOWN"
  fi
}

json_escape() {
  local string="$1"
  string="${string//\\/\\\\}"
  string="${string//\"/\\\"}"
  string="${string//$'\n'/\\n}"
  printf '%s' "$string"
}

update_stats() {
  local decision="$1"
  local signal="$2"
  local session_id="$3"
  
  local stats=$(cat "$STATS_FILE")
  local cycles=$(echo "$stats" | jq '.cycles + 1')
  
  if [[ "$decision" == "APPROVED" ]]; then
    stats=$(echo "$stats" | jq '.approvals += 1')
  elif [[ "$decision" == "REVISION_REQUIRED" ]]; then
    stats=$(echo "$stats" | jq '.revisions += 1')
  fi
  
  stats=$(echo "$stats" | jq --arg sig "$signal" '.signals += [$sig]')
  stats=$(echo "$stats" | jq --arg sid "$session_id" '.sessions += [$sid]')
  stats=$(echo "$stats" | jq ".cycles = $cycles")
  
  echo "$stats" > "$STATS_FILE"
}

delete_session() {
  local session_id="$1"
  log "Deleting session: $session_id"
  curl -s -X DELETE "$BASE/session/$session_id" >/dev/null 2>&1 || true
}

run_agent() {
  local agent_type="$1"  # "impl" or "rev"
  local prompt="$2"
  local cycle_num="$3"
  
  local model_spec=""
  local agent_name=""
  if [[ "$agent_type" == "impl" ]]; then
    model_spec='"providerID":"zai-coding-plan","modelID":"glm-4.7"'
    agent_name="ralph-implementer"
  else
    model_spec='"providerID":"openai","modelID":"gpt-5.2","variant":"high"'
    agent_name="ralph-reviewer"
  fi
  
  # Create session
  local session_id=$(curl -s -X POST "$BASE/session" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"ralph-${agent_type}-c${cycle_num}-$(date +%s)\"}" | jq -r '.id')
  
  log "Created session: $session_id for $agent_name"
  
  local escaped=$(json_escape "$prompt")
  
  # Run agent
  log "Calling $agent_name..."
  local response=$(timeout 120 curl -s -X POST "$BASE/session/$session_id/message" \
    -H "Content-Type: application/json" \
    -d "{\"model\":{$model_spec},\"agent\":\"$agent_name\",\"parts\":[{\"type\":\"text\",\"text\":\"$escaped\"}]}")
  
  # Log full response
  echo "$response" > "$TEST_DIR/logs/${agent_type}_c${cycle_num}_$(date +%s).json"
  
  # Delete session after use
  delete_session "$session_id"
  
  # Extract text
  echo "$response" | jq -r '.parts[]?.text' 2>/dev/null || echo "$response"
}

main() {
  header "🧪 RALPH STABILITY TEST - 5 CYCLES"
  log "Test directory: $TEST_DIR"
  log "Workspace: $WORKSPACE"
  log ""
  
  # Record test start
  echo "{\"test\":\"ralph-stability\",\"start\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$TEST_DIR/test_metadata.json"
  
  cat "$WORKSPACE/RALPH_TASK.md"
  log ""
  
  read -p "Start stability test? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Test aborted"
    exit 0
  fi
  
  log ""
  
  local total=0
  local successful=0
  local failed=0
  
  while [[ $total -lt 20 ]]; do
    ((total++))
    local criterion=$(get_next_criterion)
    
    if [[ -z "$criterion" ]]; then
      log ""
      header "🎉 ALL CYCLES COMPLETE!"
      break
    fi
    
    header "📍 Cycle $total"
    log "Criterion: $criterion"
    log ""
    
    local cycle_successful=false
    local retry=0
    local impl_session_id=""
    local rev_session_id=""
    
    while [[ $retry -lt 3 ]]; do
      log "Attempt $((retry+1))/3"
      
      # IMPLEMENTER
      info "🟢 IMPLEMENTER (glm-4.7)"
      local impl_prompt="Implement: $criterion

CRITICAL: After creating files, RUN: git add -A
This ensures the reviewer can see your changes.

Output: IMPLEMENTATION_COMPLETE when done."
      
      local impl_output=$(run_agent "impl" "$impl_prompt" "$total")
      echo "$impl_output" > "$TEST_DIR/logs/impl_c${total}_a${retry}.txt"
      
      # Check for IMPLEMENTATION_COMPLETE
      if ! echo "$impl_output" | grep -q "IMPLEMENTATION_COMPLETE"; then
        log "⚠️  No IMPLEMENTATION_COMPLETE signal from implementer"
      fi
      
      log ""
      
      # REVIEWER
      info "🔴 REVIEWER (gpt-5.2 HIGH)"
      local review_prompt="Review the git changes for: $criterion

Check: git diff HEAD~1
Output ONLY:
✅ APPROVED: [one-line reason]
🔴 REVISION_REQUIRED: [specific issue]"
      
      local rev_output=$(run_agent "rev" "$review_prompt" "$total")
      echo "$rev_output" > "$TEST_DIR/logs/rev_c${total}_a${retry}.txt"
      
      # Parse decision
      local decision=$(parse_reviewer_output "$rev_output")
      local signal=$(echo "$rev_output" | grep -E "✅ APPROVED|🔴 REVISION_REQUIRED" | head -1)
      
      if [[ -z "$signal" ]]; then
        signal="(no signal detected)"
      fi
      
      log "Decision: $decision"
      log "Signal: $signal"
      log ""
      
      # Update stats
      update_stats "$decision" "$signal" "session-ignored"
      
      if [[ "$decision" == "APPROVED" ]]; then
        info "✅ Cycle $total: APPROVED"
        
        git add -A 2>/dev/null || true
        git commit -m "ralph-stability: $criterion" >/dev/null 2>&1 || true
        mark_complete "$criterion"
        
        ((successful++))
        cycle_successful=true
        break
        
      elif [[ "$decision" == "REVISION_REQUIRED" ]]; then
        ((retry++))
        
        if [[ $retry -ge 3 ]]; then
          error "❌ Cycle $total: MAX RETRIES"
          ((failed++))
          cycle_successful=false
          break
        fi
        
        warn "🔄 Retry $retry/3"
        log "Will retry..."
        log ""
        
      else
        warn "⚠️  Unknown response - treating as revision"
        ((retry++))
        log "Will retry..."
        log ""
      fi
    done
    
    # Progress
    local remaining=$(grep -c '\[ \]' "$WORKSPACE/RALPH_TASK.md" || true)
    log "Progress: $successful/$total successful, $remaining remaining, $failed failed"
    log ""
  done
  
  # Record test end
  echo "{\"test\":\"ralph-stability\",\"end\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$TEST_DIR/test_metadata.json"
  
  # Final summary
  header "📊 TEST RESULTS"
  log ""
  
  local stats=$(cat "$STATS_FILE")
  log "📈 Statistics:"
  log "   Total cycles:    $(echo "$stats" | jq '.cycles')"
  log "   Approvals:       $(echo "$stats" | jq '.approvals')"
  log "   Revisions:       $(echo "$stats" | jq '.revisions')"
  log "   Failures:         $(echo "$stats" | jq '.failures')"
  log "   Signals captured: $(echo "$stats" | jq '.signals | length')"
  log "   Sessions created: $(echo "$stats" | jq '.sessions | length')"
  log ""
  
  log "📁 Logs saved in: $TEST_DIR/logs/"
  log ""
  
  # List all signal outputs
  log "🔍 All Signals Detected:"
  echo "$stats" | jq -r '.signals[]' | while read sig; do
    log "   $sig"
  done
  log ""
  
  # Success criteria
  log "✅ Success Criteria Check:"
  
  local files_created=$(ls -la t*.txt 2>/dev/null | wc -l | tr -d ' ')
  log "   Files created: $files_created/5"
  
  local success_rate=$(( successful * 100 / (total > 0 ? total : 1) ))
  log "   Success rate: ${success_rate}%"
  log "   Failures: $failed"
  
  if [[ $successful -ge 5 ]] && [[ $failed -eq 0 ]]; then
    info "✅ STABILITY TEST PASSED!"
  elif [[ $failed -gt 0 ]]; then
    error "❌ STABILITY TEST FAILED: $failed failures"
  else
    warn "⚠️  TEST INCOMPLETE: Only $successful cycles completed"
  fi
  
  log ""
  log "📝 Final task status:"
  cat "$WORKSPACE/RALPH_TASK.md"
}

main "$@"
