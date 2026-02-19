#!/bin/bash
# ============================================================
# HISTORICAL - Migration complete 2026-02-18
# Do not use. Kept for migration record only.
# ============================================================

#!/bin/bash
# rollout-external-beads-all-vms.sh
# Orchestrate external beads database rollout across all VMs.
#
# Usage:
#   ./scripts/rollout-external-beads-all-vms.sh [--dry-run] [--vm VM_NAME]
#
# Options:
#   --dry-run    Show what would happen without making changes
#   --vm VM_NAME Run on specific VM only (homedesktop-wsl|macmini|epyc6)
#
# This script:
#   - Runs migration on each VM
#   - Verifies success before proceeding
#   - Provides clear status output
#   - Can be run from any VM

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# SSH targets for each VM
VM_HOMEDESKTOP_WSL="${VM_HOMEDESKTOP_WSL:-homedesktop-wsl}"
VM_MACMINI="${VM_MACMINI:-macmini}"
VM_EPYC6="${VM_EPYC6:-epyc6}"

# Agent-skills repo location on each VM
REPO_PATH="\$HOME/agent-skills"
MIGRATION_SCRIPT="\$HOME/agent-skills/scripts/migrate-to-external-beads.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Dry run flag
DRY_RUN=""

# =============================================================================
# LOGGING
# =============================================================================

log() {
    local level="$1"
    shift
    echo -e "${level} $*"
}

log_info() { log "${BLUE}[INFO]${NC}" "$*"; }
log_success() { log "${GREEN}[SUCCESS]${NC}" "$*"; }
log_warning() { log "${YELLOW}[WARNING]${NC}" "$*"; }
log_error() { log "${RED}[ERROR]${NC}" "$*"; }

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

TARGET_VM=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN="--dry-run"
            shift
            ;;
        --vm)
            TARGET_VM="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--vm VM_NAME]"
            exit 1
            ;;
    esac
done

# =============================================================================
# SSH EXECUTION
# =============================================================================

run_on_vm() {
    local vm="$1"
    local cmd="$2"
    local ssh_target

    case "$vm" in
        homedesktop-wsl)
            ssh_target="$VM_HOMEDESKTOP_WSL"
            ;;
        macmini)
            ssh_target="$VM_MACMINI"
            ;;
        epyc6)
            ssh_target="$VM_EPYC6"
            ;;
        *)
            log_error "Unknown VM: $vm"
            return 1
            ;;
    esac

    log_info "Running on $vm ($ssh_target)..."

    if [ -n "$DRY_RUN" ]; then
        log_info "[DRY-RUN] Would execute on $vm: $cmd"
        return 0
    fi

    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$ssh_target" "$cmd" 2>&1 || {
        log_error "Command failed on $vm"
        return 1
    }
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

check_vm_connectivity() {
    local vm="$1"
    local ssh_target

    case "$vm" in
        homedesktop-wsl) ssh_target="$VM_HOMEDESKTOP_WSL" ;;
        macmini) ssh_target="$VM_MACMINI" ;;
        epyc6) ssh_target="$VM_EPYC6" ;;
    esac

    log_info "Checking connectivity to $vm..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_target" "echo OK" >/dev/null 2>&1; then
        log_success "✓ $vm is reachable"
        return 0
    else
        log_warning "⚠ $vm is not reachable (will skip)"
        return 1
    fi
}

check_script_exists() {
    local vm="$1"

    log_info "Checking migration script exists on $vm..."
    local cmd="[ -f $MIGRATION_SCRIPT ] && echo 'EXISTS' || echo 'MISSING'"
    local result=$(run_on_vm "$vm" "$cmd" 2>/dev/null || echo "FAILED")

    if [ "$result" = "EXISTS" ]; then
        log_success "✓ Migration script found on $vm"
        return 0
    else
        log_error "✗ Migration script NOT found on $vm"
        log_info "  Pull latest agent-skills first: cd $REPO_PATH && git pull"
        return 1
    fi
}

# =============================================================================
# MIGRATION EXECUTION
# =============================================================================

run_migration() {
    local vm="$1"
    local dry_flag="${DRY_RUN:-}"

    log_info "Starting migration on $vm..."

    # Run the migration
    local cmd="cd $REPO_PATH && bash $MIGRATION_SCRIPT ${dry_flag} --force"
    local output
    output=$(run_on_vm "$vm" "$cmd" 2>&1)
    local exit_code=$?

    echo "$output"

    if [ $exit_code -eq 0 ]; then
        log_success "✓ Migration completed on $vm"

        # Verify BEADS_DIR is set
        log_info "Verifying BEADS_DIR on $vm..."
        local verify_cmd="source ~/.bashrc >/dev/null 2>&1 && echo \\\$BEADS_DIR"
        local beads_dir=$(run_on_vm "$vm" "$verify_cmd" 2>/dev/null | tail -1)

        if [ -n "$beads_dir" ]; then
            log_success "✓ BEADS_DIR verified: $beads_dir"
        else
            log_warning "⚠ BEADS_DIR not verified (may need shell restart)"
        fi

        return 0
    else
        log_error "✗ Migration failed on $vm"
        log_info "  Check log on $vm: ~/.beads-migration.log"
        return 1
    fi
}

# =============================================================================
# POST-FLIGHT VERIFICATION
# =============================================================================

verify_cross_vm_sync() {
    log_info "Verifying cross-VM consistency..."

    # Skip verification in dry-run
    if [ -n "$DRY_RUN" ]; then
        log_info "[DRY-RUN] Would verify cross-VM consistency"
        return 0
    fi

    # Get issue count from each VM
    local counts=()
    for vm in homedesktop-wsl macmini epyc6; do
        if ! check_vm_connectivity "$vm" 2>/dev/null; then
            continue
        fi

        local cmd="source ~/.bashrc >/dev/null 2>&1 && bd list 2>/dev/null | wc -l"
        local count=$(run_on_vm "$vm" "$cmd" 2>/dev/null | tail -1 || echo "0")
        counts+=("$vm:$count")
        log_info "  $vm: $count issues"
    done

    # Check if counts are similar (allowing for some skew during sync)
    if [ ${#counts[@]} -gt 1 ]; then
        log_info "Issue counts across VMs:"
        for item in "${counts[@]}"; do
            echo "  $item"
        done
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "=== External Beads Database Rollout ==="
    log_info "Dry run: ${DRY_RUN:-false}"
    log_info "Target VM: ${TARGET_VM:-all}"
    echo ""

    # Determine which VMs to migrate
    local vms=()
    if [ -n "$TARGET_VM" ]; then
        vms=("$TARGET_VM")
    else
        vms=(homedesktop-wsl macmini epyc6)
    fi

    # Pre-flight checks
    log_info "Running pre-flight checks..."
    echo ""

    local ready_vms=()
    for vm in "${vms[@]}"; do
        if check_vm_connectivity "$vm" && check_script_exists "$vm"; then
            ready_vms+=("$vm")
        fi
    done

    if [ ${#ready_vms[@]} -eq 0 ]; then
        log_error "No VMs ready for migration"
        exit 1
    fi

    echo ""

    # Execute migrations
    local succeeded=()
    local failed=()

    for vm in "${ready_vms[@]}"; do
        echo "========================================"
        if run_migration "$vm"; then
            succeeded+=("$vm")
        else
            failed+=("$vm")
        fi
        echo ""
    done

    # Summary
    log_info "=== Rollout Summary ==="
    echo ""

    if [ ${#succeeded[@]} -gt 0 ]; then
        log_success "Succeeded: ${succeeded[*]}"
    fi

    if [ ${#failed[@]} -gt 0 ]; then
        log_error "Failed: ${failed[*]}"
        log_info "Check logs on failed VMs: ~/.beads-migration.log"
    fi

    # Cross-VM verification
    if [ ${#succeeded[@]} -gt 1 ]; then
        verify_cross_vm_sync
    fi

    # Exit code
    if [ ${#failed[@]} -gt 0 ]; then
        exit 1
    fi
}

main
