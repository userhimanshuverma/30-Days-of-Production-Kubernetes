# 📊 Kubecost / OpenCost Setup Guide

This guide details installing, configuring, and querying Kubecost/OpenCost to establish real-time cost transparency for Kubernetes clusters.

---

## 1. Installation via Helm

Kubecost relies on Prometheus for collecting metrics and scrapes cloud provider APIs directly to determine exact billing rates.

### Step 1: Add Kubecost Helm Repository
```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm repo update
```

### Step 2: Create a Custom Value File (`values.yaml`)
Create `kubecost-values.yaml` to optimize memory footprints and configure integration:

```yaml
global:
  prometheus:
    enabled: true
    # Use existing Prometheus if you have one, else let Kubecost deploy its lightweight version
    kube-state-metrics:
      disabled: false
  
  # Configure Cloud Provider Integration (AWS example)
  # Allows Kubecost to get accurate Spot prices and discount agreements
  awsSavingsPlans: true

kubecostProductConfigs:
  clusterName: production-cluster-01
  currencyCode: USD
  # Allocate idle resources proportionally to tenants
  shareIdle: "true"
  # Distribute kube-system costs across namespaces
  shareNamespaces: "kube-system,monitoring,logging"

# Disable components that are unnecessary for basic cost reporting to save memory
kubecostModel:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: "1"
      memory: 2Gi
```

### Step 3: Install the Release
```bash
helm upgrade --install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  -f kubecost-values.yaml
```

---

## 2. Accessing the Kubecost Dashboard

Port-forward the cost-analyzer service to access the UI:

```bash
kubectl port-forward --namespace kubecost deployment/kubecost-cost-analyzer 9090:9090
```

Open `http://localhost:9090` in your web browser. You will see:
* Cluster efficiency scores.
* Breakdowns by Namespace, Deployment, and Service.
* Dynamic right-sizing recommendations.
* Abandoned resource lists (e.g., PVs with no active Pod mounts).

---

## 3. Querying Cost Data via API

For automation, CI/CD gates, or custom reporting, query the Kubecost API directly.

### Querying Namespace Allocation (Last 7 Days)
```bash
curl -X GET "http://localhost:9090/model/allocation" \
  -d window="7d" \
  -d aggregate="namespace" \
  -d accumulate="true" | jq .
```

#### Expected API Output:
```json
{
  "code": 200,
  "status": "success",
  "data": [
    {
      "default": {
        "name": "default",
        "cpuCost": 12.45,
        "gpuCost": 0.0,
        "ramCost": 8.12,
        "pvCost": 4.50,
        "networkCost": 2.15,
        "sharedCost": 5.20,
        "totalCost": 32.42,
        "efficiency": 0.42
      },
      "payment-gateway-prod": {
        "name": "payment-gateway-prod",
        "cpuCost": 245.80,
        "gpuCost": 0.0,
        "ramCost": 198.40,
        "pvCost": 80.00,
        "networkCost": 45.20,
        "sharedCost": 42.10,
        "totalCost": 611.50,
        "efficiency": 0.89
      }
    }
  ]
}
```

---

## 4. Key Prometheus Metrics to Alert On

Kubecost exports metrics directly to Prometheus, allowing custom Grafana dashboards and Prometheus Alerts.

* `node_cpu_hourly_cost`: Cost of a node's CPU per hour.
* `node_ram_gb_hourly_cost`: Cost of a node's RAM per hour.
* `container_cpu_allocation_cost`: Calculated hourly cost for container CPU requests.
* `container_memory_allocation_cost`: Calculated hourly cost for container RAM requests.

### Prometheus Alert Rule: High Waste Detection
Create a alert rule when cluster cost efficiency drops below 50% for more than 4 hours:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cluster-waste-alert
  namespace: monitoring
spec:
  groups:
  - name: kubecost.rules
    rules:
    - alert: LowClusterEfficiency
      expr: sum(container_cpu_allocation_cost) / sum(node_cpu_hourly_cost) < 0.50
      for: 4h
      labels:
        severity: warning
        team: finops
      annotations:
        summary: "Cluster efficiency is critically low ({{ $value | printf \"%.2f\" }}%)"
        description: "Cluster resource requests account for less than 50% of active node capacity cost. Nodes are under-allocated. Review right-sizing guidelines."
```
