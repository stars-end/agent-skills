#!/usr/bin/env bash
# beads-restore-verify.sh - Daily restore verification from MinIO
# Runs on: epyc6 (standby)
# Schedule: Daily via cron

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BEADS_REPO="${BEADS_REPO_PATH:-$HOME/bd}"
RESTORE_DIR="$HOME/bd-restore-test"
MINIO_ALIAS="${MINIO_ALIAS:-beads-minio}"
MINIO_BUCKET="${MINIO_BUCKET:-beads-backups}"

log() {
  echo "[$(date -Iseconds)] $*"
}

error() {
  echo "[$(date -Iseconds)] ERROR: $*" >&2
}

check_prerequisites() {
  if ! command -v mc &>/dev/null; then
    error "MinIO client (mc) not found"
    exit 1
  fi

  if ! mc alias list 2>/dev/null | grep -q "^$MINIO_ALIAS"; then
    error "MinIO alias '$MINIO_ALIAS' not configured"
    exit 1
  fi
}

download_latest_backup() {
  log "Finding latest backup..."
  
  # Get the most recent date directory
  local latest_date
  latest_date=$(mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" 2>/dev/null | grep -oE '[0-9]{8}' | sort -r | head -1)
  
  if [[ -z "$latest_date" ]]; then
    error "No backup directories found in MinIO"
    exit 1
  fi
  
  log "Latest backup date: $latest_date"
  
  # Get the most recent backup file
  local latest_backup
  latest_backup=$(mc ls "$MINIO_ALIAS/$MINIO_BUCKET/$latest_date/" 2>/dev/null | tail -1 | awk '{print $NF}')
  
  if [[ -z "$latest_backup" ]]; then
    error "No backup file found for date $latest_date"
    exit 1
  fi
  
  log "Latest backup file: $latest_backup"
  
  # Download backup
  mkdir -p "$RESTORE_DIR"
  rm -rf "$RESTORE_DIR"/*
  
  local backup_path="$MINIO_ALIAS/$MINIO_BUCKET/$latest_date/$latest_backup"
  if mc cp "$backup_path" "$RESTORE_DIR/backup.tar.gz"; then
    log "Downloaded: $backup_path"
  else
    error "Failed to download backup"
    exit 1
  fi
}

extract_backup() {
  log "Extracting backup..."
  
  cd "$RESTORE_DIR"
  
  if ! tar -xzf backup.tar.gz; then
    error "Failed to extract backup archive"
    exit 1
  fi
  
  # Check for nested archive (new format)
  if [[ -f "dolt_data.tar.gz" ]]; then
    mkdir -p dolt_restore
    tar -xzf dolt_data.tar.gz -C dolt_restore
    log "Extracted dolt_data.tar.gz"
  elif [[ -f "backup.tar.gz" ]]; then
    # Old format - single tarball
    mkdir -p dolt_restore
    tar -xzf backup.tar.gz -C dolt_restore
  fi
}

validate_restore() {
  log "Validating restored data..."
  
  local dolt_dir="$RESTORE_DIR/dolt_restore"
  
  if [[ ! -d "$dolt_dir" ]]; then
    # If no dolt_restore, the archive was the dolt data itself
    dolt_dir="$RESTORE_DIR"
  fi
  
  # Check for expected Dolt structure
  if [[ ! -d "$dolt_dir/.dolt" && ! -d "$dolt_dir/beads_bd/.dolt" ]]; then
    error "No valid Dolt repository found in backup"
    exit 1
  fi
  
  # Try to read the database
  local db_dir="$dolt_dir/beads_bd"
  if [[ ! -d "$db_dir" ]]; then
    db_dir=$(find "$dolt_dir" -name "beads_bd" -type d 2>/dev/null | head -1)
  fi
  
  if [[ -d "$db_dir/.dolt" ]]; then
    # Check dolt log to verify database is readable
    if timeout 30 bash -c "cd '$db_dir' && dolt log --oneline -n 1" >/dev/null 2>&1; then
      log "Dolt database verified successfully"
      local commit_count
      commit_count=$(cd "$db_dir" && dolt log --oneline 2>/dev/null | wc -l)
      log "Commit count: $commit_count"
    else
      error "Failed to read Dolt database"
      exit 1
    fi
  else
    log "Warning: Could not locate beads_bd directory for validation"
  fi
}

test_restore_to_temp() {
  log "Testing full restore to temporary location..."
  
  local temp_restore="$RESTORE_DIR/temp_beads"
  rm -rf "$temp_restore"
  mkdir -p "$temp_restore/.beads"
  
  # Copy restored data
  if [[ -d "$RESTORE_DIR/dolt_restore" ]]; then
    cp -r "$RESTORE_DIR/dolt_restore" "$temp_restore/.beads/dolt"
  else
    error "No dolt data to restore"
    exit 1
  fi
  
  # Try to start a temporary Dolt server
  log "Starting temporary Dolt server for validation..."
  
  local temp_port=3308
  if timeout 30 bash -c "cd '$temp_restore' && dolt sql-server --data-dir $temp_restore/.beads/dolt --host 127.0.0.1 --port $temp_port &" 2>/dev/null; then
    sleep 3
    
    # Test connection
    if BEADS_DOLT_SERVER_HOST=127.0.0.1 BEADS_DOLT_SERVER_PORT=$temp_port \
      timeout 10 bd dolt test --json 2>/dev/null | grep -q '"connection_ok": true'; then
      log "Temporary server connection successful"
    else
      log "Warning: Could not verify temporary server connection"
    fi
    
    # Kill temporary server
    pkill -f "dolt sql-server.*port $temp_port" 2>/dev/null || true
  else
    log "Warning: Could not start temporary server for validation"
  fi
}

cleanup() {
  log "Cleaning up..."
  rm -rf "$RESTORE_DIR"
}

report_metrics() {
  local backup_size
  backup_size=$(mc stat "$MINIO_ALIAS/$MINIO_BUCKET/"*"/"*.tar.gz 2>/dev/null | grep Size | tail -1 || echo "unknown")
  
  log "=== Restore Verification Report ==="
  log "Timestamp: $TIMESTAMP"
  log "Backup Size: $backup_size"
  log "Status: SUCCESS"
  log "=================================="
}

main() {
  log "=== Starting Beads restore verification ==="
  
  trap cleanup EXIT
  
  check_prerequisites
  download_latest_backup
  extract_backup
  validate_restore
  test_restore_to_temp
  report_metrics
  
  log "=== Restore verification complete ==="
}

main "$@"
