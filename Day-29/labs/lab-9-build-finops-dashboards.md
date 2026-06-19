# Lab 9: Build FinOps Dashboards

In this lab, you will write PromQL queries and build Grafana panels to visualize cluster costs, partition costs by namespace, and identify idle capacity waste.

---

## 1. Verify Prometheus Integration
Ensure Kubecost is exporting metrics to your cluster's Prometheus registry. Query the metrics server using `kubectl`:

```bash
# Check if Kubecost metrics are present in Prometheus
kubectl exec -n monitoring prometheus-k8s-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[].discoveredLabels | select(.__address__== "kubecost-cost-analyzer.kubecost.svc.cluster.local:9003")'
```

---

## 2. PromQL Queries for Key Panels
Create three panels in your Grafana FinOps Dashboard using the following PromQL definitions:

### Panel 1: Hourly Cluster Spend Rate
*   **Metric Title**: Current Hourly Cluster Spend (USD/hr)
*   **PromQL Query**:
    ```promql
    sum(node_cpu_hourly_cost) + sum(node_ram_gb_hourly_cost * (node_memory_working_set_bytes / 1024 / 1024 / 1024))
    ```
*   **Visualization Type**: Stat / Gauge
*   **Unit**: currency ($)

### Panel 2: Cost Breakdown by Namespace
*   **Metric Title**: Cumulative Cost Share by Namespace (Last 24 Hours)
*   **PromQL Query**:
    ```promql
    sum(increase(container_cpu_allocation_cost[24h])) by (namespace) + sum(increase(container_memory_allocation_cost[24h])) by (namespace)
    ```
*   **Visualization Type**: Bar Chart or Pie Chart
*   **Unit**: currency ($)

### Panel 3: Idle Capacity (Slack Cost)
*   **Metric Title**: Idle Node Capacity Cost (Wasted Resources)
*   **PromQL Query**:
    ```promql
    (sum(node_cpu_hourly_cost) - sum(container_cpu_allocation_cost)) + 
    ((sum(node_ram_gb_hourly_cost) * sum(node_memory_working_set_bytes / 1024 / 1024 / 1024)) - sum(container_memory_allocation_cost))
    ```
*   **Visualization Type**: Time Series
*   **Unit**: currency ($/hr)

---

## 3. Importing a Pre-Built Grafana Dashboard
Instead of building panels manually, import the community standard Kubecost dashboard:

1. Log into your **Grafana UI**.
2. Navigate to **Dashboards** -> **New** -> **Import**.
3. Enter the dashboard ID: **`16301`** (or **`10851`** for standard OpenCost visualizations).
4. Select your **Prometheus data source**.
5. Click **Import**.

You will now have an interactive, live dashboard showing:
*   Total cluster cost.
*   Cost efficiency index (Goal: >75%).
*   Idle vs active CPU/Memory costs.
*   GPU cost breakouts.

---

## 4. Setting Up Alerting Thresholds in Grafana
Create an alert rule inside Grafana to trigger when Idle Cost exceeds $10/hour for more than 1 hour:

1. Click **Alerting** -> **Alert rules** -> **Create rule**.
2. Name: `High-Idle-Resource-Waste`.
3. Set the expression to the **Idle Capacity** PromQL query from Section 2.
4. Set condition: `IS ABOVE 10`.
5. Set evaluation behavior: `For 1h`.
6. Configure contact point to your `#finops-alerts` Slack channel or PagerDuty.
