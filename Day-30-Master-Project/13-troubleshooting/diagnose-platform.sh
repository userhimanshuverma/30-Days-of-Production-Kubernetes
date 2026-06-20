#!/usr/bin/env bash
set -eo pipefail

REPORT_FILE="platform_diagnosis_report.txt"
echo "=========================================="
echo "🔍 Initiating SRE Platform Diagnostic Utility"
echo "💾 Writing report to: ${REPORT_FILE}"
echo "=========================================="

{
  echo "=== SRE PLATFORM DIAGNOSTIC REPORT ==="
  echo "Timestamp: $(date -u)"
  echo "--------------------------------------"
  
  echo ""
  echo "=== [1] KUBERNETES NODE STATUS ==="
  kubectl get nodes -o wide || echo "Unable to query nodes."
  
  echo ""
  echo "=== [2] SYSTEM DEPLOYMENTS & CONTROLLERS ==="
  kubectl get deployments --all-namespaces || echo "Unable to query deployments."
  
  echo ""
  echo "=== [3] STATEFUL PERSISTENCE LAYER STATUS ==="
  echo "PostgreSQL (CloudNativePG):"
  kubectl get pods -n databases -o wide || echo "No postgres pods found."
  echo "Kafka (Strimzi):"
  kubectl get pods -n kafka -o wide || echo "No kafka pods found."
  
  echo ""
  echo "=== [4] WORKLOAD STATES (AI SERVICES) ==="
  kubectl get pods -n ai-services -o wide || echo "No workload pods found."
  
  echo ""
  echo "=== [5] INGRESS & TLS ROUTING CONFIGURATIONS ==="
  kubectl get ingress -A || echo "No ingress endpoints found."
  kubectl get certificate -A || echo "No TLS certificates found."
  
  echo ""
  echo "=== [6] DETECTED ERROR EVENTS (LAST 10 MINUTES) ==="
  kubectl get events -A --field-selector type!=Normal | tail -n 25 || echo "No recent error events found."

  echo ""
  echo "=== [7] CRASHED/RESTARTING CONTAINERS ANALYSIS ==="
  kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '$3 > 0 {print "Namespace: "$1", Pod: "$2", Restarts: "$3}' || echo "No restarting pods detected."

} > "${REPORT_FILE}"

echo "=========================================="
echo "✅ Diagnosis completed successfully!"
echo "📄 Review findings in ${REPORT_FILE}"
echo "=========================================="
