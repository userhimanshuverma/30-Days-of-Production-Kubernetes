#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "🚀 Bootstrapping Local Multi-Node Kind Cluster"
echo "=========================================="

# Check requirements
if ! command -v kind &> /dev/null; then
    echo "❌ Error: kind CLI is not installed."
    exit 1
fi

CLUSTER_NAME="multi-node-dev"

# Define cluster config as a heredoc
read -r -d '' CLUSTER_CONFIG <<EOF || true
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  image: kindest/node:v1.27.3
- role: worker
  image: kindest/node:v1.27.3
- role: worker
  image: kindest/node:v1.27.3
EOF

# Create cluster
echo "⚙️ Creating cluster ${CLUSTER_NAME}..."
echo "${CLUSTER_CONFIG}" | kind create cluster --config -

echo "🎉 Cluster created successfully! Verifying..."
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
kubectl get nodes

echo "=========================================="
echo "✅ Local Dev Cluster ready!"
echo "=========================================="
