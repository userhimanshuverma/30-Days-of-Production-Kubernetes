#!/usr/bin/env bash
# ==============================================================================
# SRE Automation Script: etcd-backup.sh
# Purpose: Secures, validates, and archives Kubernetes etcd snapshots.
# Recommended execution: CRON on control-plane nodes, or inside Kubernetes cronjobs.
# ==============================================================================

set -euo pipefail

# --- Configurations ---
BACKUP_DIR="${BACKUP_DIR:-/var/backups/kubernetes/etcd}"
ETCD_PKI_DIR="${ETCD_PKI_DIR:-/etc/kubernetes/pki/etcd}"
ETCD_ENDPOINT="${ETCD_ENDPOINT:-https://127.0.0.1:2379}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# TLS Credentials
CA_CERT="${ETCD_PKI_DIR}/ca.crt"
SERVER_CERT="${ETCD_PKI_DIR}/server.crt"
SERVER_KEY="${ETCD_PKI_DIR}/server.key"

# Timestamp format
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
SNAPSHOT_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"

# --- Logging Functions ---
log_info()  { echo -e "\033[1;32m[INFO]\033[0m  [$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  [$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m [$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2; }

# --- Pre-flight Checks ---
check_prerequisites() {
  log_info "Running pre-flight checks..."
  
  # Check if running as root (required to read certificates and write to backup folder)
  if [[ $EUID -ne 0 ]]; then
     log_error "This script must be run as root (or via sudo)."
     exit 1
  fi

  # Check if etcdctl is installed
  if ! command -v etcdctl &> /dev/null; then
    log_error "etcdctl binary not found in PATH."
    exit 1
  fi
  
  # Enable ETCDCTL_API=3
  export ETCDCTL_API=3
  
  # Verify TLS certificates exist
  for cert in "$CA_CERT" "$SERVER_CERT" "$SERVER_KEY"; do
    if [[ ! -f "$cert" ]]; then
      log_error "Required certificate/key not found: $cert"
      exit 1
    fi
  done
  
  # Ensure backup directory exists
  mkdir -p "$BACKUP_DIR"
}

# --- Perform Backup ---
take_snapshot() {
  log_info "Taking etcd snapshot of cluster..."
  
  # Execute snapshot save command
  if etcdctl \
    --endpoints="$ETCD_ENDPOINT" \
    --cacert="$CA_CERT" \
    --cert="$SERVER_CERT" \
    --key="$SERVER_KEY" \
    snapshot save "$SNAPSHOT_FILE" > /dev/null; then
    
    log_info "Snapshot completed and stored: ${SNAPSHOT_FILE}"
  else
    log_error "Failed to take etcd snapshot!"
    exit 2
  fi
}

# --- Validate Backup ---
validate_snapshot() {
  log_info "Validating snapshot integrity..."
  
  # etcdctl snapshot status returns non-zero if corrupt
  if etcdctl --write-out=table snapshot status "$SNAPSHOT_FILE"; then
    log_info "Integrity check PASSED for: ${SNAPSHOT_FILE}"
  else
    log_error "Snapshot file is corrupt or invalid! Deleting file."
    rm -f "$SNAPSHOT_FILE"
    exit 3
  fi
}

# --- Cleanup Old Backups ---
prune_old_backups() {
  log_info "Pruning backups older than ${RETENTION_DAYS} days..."
  
  # Find files matching name pattern older than retention threshold and delete them
  local deleted_count
  deleted_count=$(find "$BACKUP_DIR" -name "etcd-snapshot-*.db" -type f -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
  
  log_info "Pruned ${deleted_count} stale backup file(s)."
}

# --- Main Execution ---
main() {
  check_prerequisites
  take_snapshot
  validate_snapshot
  prune_old_backups
  log_info "Backup workflow executed successfully."
}

main "$@"
