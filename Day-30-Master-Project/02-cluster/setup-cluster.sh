#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "🚀 Creating HA Production-Grade Kind Cluster"
echo "=========================================="

# Check dependencies
if ! command -v kind &> /dev/null; then
    echo "❌ Error: kind CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl CLI is not installed. Please install it first."
    exit 1
fi

# Locate the config directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/kind-ha-config.yaml"

if [ ! -f "${CONFIG_PATH}" ]; then
    echo "❌ Error: Config file not found at ${CONFIG_PATH}"
    exit 1
fi

# Spin up cluster
echo "⚙️  Initializing cluster using configuration: ${CONFIG_PATH}..."
kind create cluster --config "${CONFIG_PATH}"

echo "🎉 Cluster deployed successfully! Verifying node status..."
kubectl get nodes -o wide

echo "📋 Verifying system pod status..."
kubectl get pods -n kube-system

echo "=========================================="
echo "✅ Cluster is ready for workloads!"
echo "=========================================="
