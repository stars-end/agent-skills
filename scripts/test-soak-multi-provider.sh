#!/usr/bin/env bash
# test-soak-multi-provider.sh - 6-stream mixed-provider soak run
#
# Validates bd-xga8.14.7 acceptance criteria:
# - 6 concurrent jobs across 3 providers (2 per provider)
# - cc-glm, opencode, gemini all tested
# - Output JSON + markdown summary with taxonomy
# - Proves bd-cbsb.14-.18 acceptance criteria met through unified path

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
DX_RUNNER="${ROOT_DIR}/scripts/dx-runner"

SOAK_DIR="/tmp/dx-runner-soak-$$"
RESULTS_DIR="${SOAK_DIR}/results"
mkdir -p "$RESULTS_DIR"

TIMESTAMP="$(date +%Y%m%d%H%M%S)"

echo "=== Multi-Provider Soak Test ==="
echo "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Results dir: $RESULTS_DIR"
echo ""

# Create simple test prompts
create_test_prompt() {
    local name="$1"
    cat > "${SOAK_DIR}/${name}.prompt" <<EOF
You are a test agent for a soak test. Please respond with exactly:
READY: $name
Do not do anything else. Just respond with that single line.
EOF
}

# Provider configurations
declare -A PROVIDER_JOBS=(
    ["cc-glm-test1"]="cc-glm"
    ["cc-glm-test2"]="cc-glm"
    ["opencode-test1"]="opencode"
    ["opencode-test2"]="opencode"
    ["gemini-test1"]="gemini"
    ["gemini-test2"]="gemini"
)

# Create prompts
for job in "${!PROVIDER_JOBS[@]}"; do
    create_test_prompt "$job"
done

# Run preflight for each provider
echo "=== Preflight Checks ==="
for provider in cc-glm opencode gemini; do
    echo "Preflight: $provider"
    if "$DX_RUNNER" preflight --provider "$provider" >"${RESULTS_DIR}/${provider}-preflight.log" 2>&1; then
        echo "  ✓ PASSED"
    else
        echo "  ✗ FAILED (see ${RESULTS_DIR}/${provider}-preflight.log)"
    fi
done
echo ""

# Start jobs
echo "=== Starting Jobs ==="
declare -A JOB_PIDS
for job in "${!PROVIDER_JOBS[@]}"; do
    provider="${PROVIDER_JOBS[$job]}"
    echo "Starting: $job (provider=$provider)"
    
    if "$DX_RUNNER" start \
        --beads "$job" \
        --provider "$provider" \
        --prompt-file "${SOAK_DIR}/${job}.prompt" \
        >"${RESULTS_DIR}/${job}-start.log" 2>&1; then
        echo "  ✓ Started"
    else
        echo "  ✗ Failed (see ${RESULTS_DIR}/${job}-start.log)"
    fi
    
    # Small delay between starts
    sleep 1
done
echo ""

# Wait for jobs to process
echo "=== Waiting for jobs (30s) ==="
sleep 30
echo ""

# Check status of all jobs
echo "=== Status Check ==="
"$DX_RUNNER" status --json > "${RESULTS_DIR}/status.json" 2>&1
"$DX_RUNNER" status 2>&1 | tee "${RESULTS_DIR}/status.log"
echo ""

# Check each job
echo "=== Individual Job Checks ==="
for job in "${!PROVIDER_JOBS[@]}"; do
    echo "Checking: $job"
    "$DX_RUNNER" check --beads "$job" --json > "${RESULTS_DIR}/${job}-check.json" 2>&1 || true
    "$DX_RUNNER" check --beads "$job" 2>&1 | tee "${RESULTS_DIR}/${job}-check.log" || true
done
echo ""

# Generate reports
echo "=== Reports ==="
for job in "${!PROVIDER_JOBS[@]}"; do
    echo "Report: $job"
    "$DX_RUNNER" report --beads "$job" --format json > "${RESULTS_DIR}/${job}-report.json" 2>&1 || true
    "$DX_RUNNER" report --beads "$job" --format markdown > "${RESULTS_DIR}/${job}-report.md" 2>&1 || true
done
echo ""

# Stop all jobs
echo "=== Stopping Jobs ==="
for job in "${!PROVIDER_JOBS[@]}"; do
    echo "Stopping: $job"
    "$DX_RUNNER" stop --beads "$job" > "${RESULTS_DIR}/${job}-stop.log" 2>&1 || true
done
echo ""

# Generate summary
SUMMARY_FILE="${RESULTS_DIR}/soak-summary.md"

cat > "$SUMMARY_FILE" <<EOF
# Multi-Provider Soak Test Summary

**Timestamp**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Run ID**: soak-${TIMESTAMP}

## Jobs

| Job | Provider | Status |
|-----|----------|--------|
EOF

for job in "${!PROVIDER_JOBS[@]}"; do
    provider="${PROVIDER_JOBS[$job]}"
    status="unknown"
    if [[ -f "${RESULTS_DIR}/${job}-check.json" ]]; then
        status="$(jq -r '.state // "unknown"' "${RESULTS_DIR}/${job}-check.json" 2>/dev/null)" || status="parse_error"
    fi
    echo "| $job | $provider | $status |" >> "$SUMMARY_FILE"
done

cat >> "$SUMMARY_FILE" <<EOF

## Preflight Results

| Provider | Status |
|----------|--------|
EOF

for provider in cc-glm opencode gemini; do
    if grep -q "PASSED" "${RESULTS_DIR}/${provider}-preflight.log" 2>/dev/null; then
        echo "| $provider | ✓ PASSED |" >> "$SUMMARY_FILE"
    else
        echo "| $provider | ✗ FAILED |" >> "$SUMMARY_FILE"
    fi
done

cat >> "$SUMMARY_FILE" <<EOF

## Failure Taxonomy

EOF

# Collect failure reasons
for job in "${!PROVIDER_JOBS[@]}"; do
    if [[ -f "${RESULTS_DIR}/${job}-check.json" ]]; then
        reason="$(jq -r '.reason_code // "none"' "${RESULTS_DIR}/${job}-check.json" 2>/dev/null)" || reason="parse_error"
        if [[ "$reason" != "none" && "$reason" != "null" ]]; then
            echo "- $job: $reason" >> "$SUMMARY_FILE"
        fi
    fi
done

cat >> "$SUMMARY_FILE" <<EOF

## Files

- JSON Status: status.json
- Per-job reports: *-report.json, *-report.md
- Preflight logs: *-preflight.log

## Acceptance Criteria

- [ ] 6 jobs started (2 per provider)
- [ ] All providers respond to preflight
- [ ] JSON output is valid and deterministic
- [ ] Markdown summary generated
- [ ] Failure taxonomy captured
EOF

# Print summary
echo "=== Summary ==="
cat "$SUMMARY_FILE"
echo ""

# Create combined JSON report
COMBINED_JSON="${RESULTS_DIR}/soak-report.json"

jq -n \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg run_id "soak-${TIMESTAMP}" \
    --slurpfile status "${RESULTS_DIR}/status.json" \
    '. + {timestamp: $timestamp, run_id: $run_id, status: $status}' \
    > "$COMBINED_JSON" 2>/dev/null || echo '{"error": "could not combine JSON"}' > "$COMBINED_JSON"

echo "Results saved to: $RESULTS_DIR"
echo "Summary: $SUMMARY_FILE"
echo "Combined JSON: $COMBINED_JSON"
echo ""
echo "=== Soak Test Complete ==="

# Cleanup
rm -rf "${SOAK_DIR}"/*.prompt
