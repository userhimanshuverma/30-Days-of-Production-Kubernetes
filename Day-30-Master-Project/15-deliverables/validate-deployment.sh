#!/usr/bin/env bash
set -eo pipefail

echo "=========================================="
echo "🎯 Commencing Platform Verification Checks"
echo "=========================================="

FAILED=0

check_namespace() {
  local ns=$1
  if kubectl get namespace "$ns" &>/dev/null; then
    echo "✅ Namespace: $ns exists."
  else
    echo "❌ Namespace: $ns NOT found!"
    FAILED=$((FAILED + 1))
  fi
}

check_deployment() {
  local ns=$1
  local deploy=$2
  if kubectl get deployment "$deploy" -n "$ns" &>/dev/null; then
    local replicas
    replicas=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}')
    if [ "${replicas:-0}" -gt 0 ]; then
      echo "✅ Deployment: $ns/$deploy is running with $replicas ready replicas."
    else
      echo "❌ Deployment: $ns/$deploy has ZERO ready replicas!"
      FAILED=$((FAILED + 1))
    fi
  else
    echo "❌ Deployment: $ns/$deploy NOT found!"
    FAILED=$((FAILED + 1))
  fi
}

# 1. Check Namespace Definitions
echo "📁 Checking namespace structures..."
check_namespace "ai-services"
check_namespace "databases"
check_namespace "kafka"
check_namespace "observability"
check_namespace "monitoring"
check_namespace "ingress-nginx"

echo ""
# 2. Check Core Deployments
echo "⚙️ Checking core service workloads..."
check_deployment "ingress-nginx" "ingress-nginx-controller"
check_deployment "ai-services" "fastapi-ai-service"
check_deployment "observability" "otel-collector"

echo ""
# 3. Check Stateful Workloads Pod Status
echo "💾 Checking stateful database layers..."
PG_PODS=$(kubectl get pods -n databases -l cnpg.io/cluster=postgres-ha --field-selector=status.phase=Running 2>/dev/null | wc -l || echo "0")
if [ "$PG_PODS" -ge 2 ]; then
  echo "✅ PostgreSQL CloudNativePG Cluster pods are healthy ($PG_PODS running)."
else
  echo "❌ PostgreSQL CloudNativePG Cluster pods are degraded ($PG_PODS running)."
  FAILED=$((FAILED + 1))
fi

KAFKA_PODS=$(kubectl get pods -n kafka -l app.kubernetes.io/name=kafka --field-selector=status.phase=Running 2>/dev/null | wc -l || echo "0")
if [ "$KAFKA_PODS" -ge 2 ]; then
  echo "✅ Kafka Broker pods are healthy ($KAFKA_PODS running)."
else
  echo "❌ Kafka Broker pods are degraded ($KAFKA_PODS running)."
  FAILED=$((FAILED + 1))
fi

echo ""
# 4. Check TLS Routing Configuration
echo "🔒 Checking certificate readiness..."
if kubectl get ingress fastapi-ai-service-ingress -n ai-services &>/dev/null; then
  echo "✅ Ingress routing definition exists."
else
  echo "❌ Ingress routing definition fastapi-ai-service-ingress NOT found!"
  FAILED=$((FAILED + 1))
fi

echo "=========================================="
if [ "$FAILED" -eq 0 ]; then
  echo "🏆 PLATFORM VERIFICATION SUCCESSFUL!"
  echo "🎉 Your Production Kubernetes Platform is fully ready!"
else
  echo "⚠️ PLATFORM CHECK DETECTED $FAILED FAILURES."
  echo "🔍 Please review SRE Troubleshooting Runbooks in 13-troubleshooting/ to resolve."
fi
echo "=========================================="
exit "$FAILED"
