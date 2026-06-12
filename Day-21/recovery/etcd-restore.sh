#!/usr/bin/env bash
# ==============================================================================
# SRE Automation Script: etcd-restore.sh
# Purpose: Safely restores an etcd snapshot and recovers the control plane.
# NOTE: Run this directly on the affected control plane node.
# ==============================================================================

set -euo pipefail

# --- Configurations ---
MANIFEST_DIR="/etc/kubernetes/manifests"
MANIFEST_BACKUP_DIR="/var/lib/k8s-manifest-backup"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_PKI_DIR="/etc/kubernetes/pki/etcd"

# TLS Credentials
CA_CERT="${ETCD_PKI_DIR}/ca.crt"
SERVER_CERT="${ETCD_PKI_DIR}/server.crt"
SERVER_KEY="${ETCD_PKI_DIR}/server.key"

# --- Logging Functions ---
log_info()  { echo -e "\033[1;32m[INFO]\033[0m  [$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  [$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m [$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2; }

# --- Usage instructions ---
usage() {
  echo "Usage: sudo $0 <path-to-etcd-snapshot.db>"
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

SNAPSHOT_PATH="$1"

# --- Pre-flight Checks ---
check_prerequisites() {
  log_info "Running pre-flight checks..."
  
  if [[ $EUID -ne 0 ]]; then
     log_error "This script must be run as root (or via sudo)."
     exit 1
  fi

  if [[ ! -f "$SNAPSHOT_PATH" ]]; then
    log_error "Snapshot file not found: $SNAPSHOT_PATH"
    exit 1
  fi

  if ! command -v etcdctl &> /dev/null; then
    log_error "etcdctl binary not found."
    exit 1
  fi

  export ETCDCTL_API=3
  mkdir -p "$MANIFEST_BACKUP_DIR"
}

# --- Stop Control Plane Static Pods ---
stop_control_plane() {
  log_info "Temporarily stopping kube-apiserver and etcd to freeze state..."
  
  # Moving manifests out of /etc/kubernetes/manifests stops the static pods immediately
  for component in "kube-apiserver.yaml" "etcd.yaml"; do
    if [[ -f "${MANIFEST_DIR}/${component}" ]]; then
      log_info "Disabling ${component}..."
      mv "${MANIFEST_DIR}/${component}" "${MANIFEST_BACKUP_DIR}/"
    else
      log_warn "${component} not found in ${MANIFEST_DIR}. Already disabled?"
    fi
  done
  
  log_info "Waiting for api-server and etcd containers to stop..."
  sleep 10
}

# --- Restore Snapshot ---
execute_restore() {
  log_info "Backing up existing etcd database folder..."
  if [[ -d "$ETCD_DATA_DIR" ]]; then
    local backup_path="${ETCD_DATA_DIR}-backup-$(date +%s)"
    log_warn "Moving existing data from ${ETCD_DATA_DIR} to ${backup_path}"
    mv "$ETCD_DATA_DIR" "$backup_path"
  fi

  # Read parameters from node environment
  local node_name
  node_name=$(hostname)
  local node_ip
  # Get primary IPv4 address
  node_ip=$(hostname -I | awk '{print $1}')
  
  log_info "Executing snapshot restore with node metadata:"
  log_info "  Node Name: $node_name"
  log_info "  Node IP:   $node_ip"
  
  # Run the restore process
  # etcdctl snapshot restore builds a fresh database directory from the snapshot
  if etcdctl snapshot restore "$SNAPSHOT_PATH" \
    --name="$node_name" \
    --data-dir="$ETCD_DATA_DIR" \
    --initial-cluster="${node_name}=https://${node_ip}:2380" \
    --initial-cluster-token="etcd-bootstrap-token" \
    --initial-advertise-peer-urls="https://${node_ip}:2380"; then
    
    log_info "Snapshot restore execution successful."
  else
    log_error "etcdctl snapshot restore failed!"
    exit 3
  fi
  
  # Crucial: Ensure permissions are set for the etcd user (usually runs under host group/user or root)
  # When kubeadm runs etcd container, it runs as root or uid 0 inside the container. 
  # However, to be safe, we preserve permissions.
  chown -R root:root "$ETCD_DATA_DIR"
  chmod -R 700 "$ETCD_DATA_DIR"
  log_info "Permissions verified on ${ETCD_DATA_DIR}"
}

# --- Restart Control Plane Static Pods ---
start_control_plane() {
  log_info "Re-enabling kube-apiserver and etcd static pods..."
  
  for component in "etcd.yaml" "kube-apiserver.yaml"; do
    if [[ -f "${MANIFEST_BACKUP_DIR}/${component}" ]]; then
      log_info "Restoring ${component}..."
      mv "${MANIFEST_BACKUP_DIR}/${component}" "${MANIFEST_DIR}/"
    else
      log_error "Could not find ${component} in backup dir: ${MANIFEST_BACKUP_DIR}"
    fi
  done
  
  log_info "Control plane manifests restored. Kubelet is spinning up static pods."
  log_info "Please monitor status using: kubectl get nodes"
}

# --- Main Execution ---
main() {
  check_prerequisites
  stop_control_plane
  execute_restore
  start_control_plane
  log_info "Recovery procedure complete. Check API Server status."
}

main "$@"
