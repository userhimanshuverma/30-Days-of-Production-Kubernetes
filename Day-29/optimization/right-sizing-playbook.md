# 📐 Workload Right-Sizing Playbook

This playbook provides standard formulas, PromQL queries, and strategies to align container resource requests with actual historical utilization, minimizing cluster waste while preserving reliability.

---

## 1. Right-Sizing Formulas

To perform automated right-sizing safely, we analyze metrics over a **14-day historical window** to capture weekly traffic cycles.

### A. CPU Right-Sizing Formula
CPU is a **compressible resource**. If a pod hits its CPU request limit, it is throttled, but it will not crash.

$$\text{Optimal CPU Request} = \text{Percentile}_{95}(\text{CPU Usage}_{14\text{d}}) \times 1.25$$

*   **Percentile 95**: Excludes transient startup peaks and extreme outliers, but covers normal daily traffic surges.
*   **1.25 (25% Safety Buffer)**: Provides head-room for minor traffic increases before autoscaling triggers.

### B. Memory Right-Sizing Formula
Memory is a **non-compressible resource**. If a pod runs out of memory, it is terminated immediately via **OOMKill**. Sizing memory requests requires a higher margin of safety.

$$\text{Optimal Memory Request} = \max(\text{Memory Usage}_{14\text{d}}) \times 1.30$$

*   **Max Usage**: Ensures the request accommodates the absolute peak RAM usage observed over 2 weeks.
*   **1.30 (30% Safety Buffer)**: Accommodates memory fragmentation and slow memory leaks over the pod's lifetime.

---

## 2. PromQL Queries to Find Cost Waste ("Slack")

Run these queries in Prometheus/Grafana to find which namespaces are wasting the most budget.

### Query 1: CPU Request Slack (Cores wasted per namespace)
```promql
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
-
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)
```
*   **Result**: Displays the number of CPU Cores reserved by the scheduler but sitting idle. Any value > 2 Cores in a non-production namespace is a prime candidate for reduction.

### Query 2: Memory Request Slack (GB wasted per namespace)
```promql
(
  sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace)
  -
  sum(container_memory_rss{container!=""}) by (namespace)
) / 1024 / 1024 / 1024
```
*   **Result**: The quantity of RAM (in Gigabytes) requested but not actively held in memory.

---

## 3. Operational Strategy: VPA Modes in Production

The Kubernetes Vertical Pod Autoscaler (VPA) can operate in three modes. Selecting the correct mode is critical for stability.

| VPA Mode | Action | Production Recommendation | Rationale |
|---|---|---|---|
| **Off** | Analyzes usage and writes recommendations to `status`, but takes no action. | **Highly Recommended** | Safe. Integrates with GitOps. No unexpected pod restarts. |
| **Initial** | Only assigns resources when a Pod is first created. Never restarts a running pod. | **Use with Caution** | Resource values can become stale during long pod lifetimes. |
| **Auto / Recreate** | Evicts running pods if actual usage drifts significantly from requests. | **Not Recommended for Core APIs** | Disruptive. Can cause sudden cascading restarts and service outages. |

### Enterprise GitOps Right-Sizing Loop
Instead of allowing the VPA controller to restart pods in production automatically, use the **GitOps Feedback Loop**:

```
[Prometheus Metrics] ──> [VPA Controller (Off Mode)]
                                 │
                                 ▼ (Writes recommendation to CRD)
                    [GitOps Agent / PR Creator]
                                 │
                                 ▼ (Opens GitHub Pull Request)
                       [SRE / Developer Review]
                                 │
                                 ▼ (Merges PR)
                   [ArgoCD / Flux applies new Spec]
```
1. VPA runs in `UpdateMode: "Off"`.
2. A custom controller (or open-source agent like `vpa-recommender-bot`) polls the VPA resource recommendations.
3. If the recommendation represents a >20% change and a >$50/mo savings, the bot automatically creates a **Pull Request** modifying the resource request block in the team's Helm values file.
4. Engineers review the PR, verify testing, and merge. ArgoCD syncs the changes gracefully.
