# Lab 10: Conduct Optimization Reviews

In this lab, you will run a systematic review of cluster resource utilization, categorize workloads based on risk, and generate an optimization plan.

---

## 1. Gather Cluster Efficiency Data
Run an audit script or query the Kubecost savings API to identify optimization targets:

```bash
# Get the top 10 most expensive and wasteful workloads
curl -s "http://localhost:9090/model/savings/requestRecommendations" | \
  jq -r '.recommendations[] | select(.savings > 10) | "\(.namespace)/\(.controllerName): Savings = $\(.savings)/mo (Current CPU Request: \(.currentCpuRequest) -> Rec: \(.recommendedCpuRequest))"' | \
  head -n 10
```

---

## 2. Categorize Workloads by Risk
Before applying changes, categorize workloads using this risk matrix to prevent outages:

| Workload Category | Risk Tier | Action Strategy | Approval Policy |
|---|---|---|---|
| **Tier-3 (Stateless Workers, Dev env)** | Low | Apply VPA Recommendations immediately. | Automated PR merge. |
| **Tier-2 (Internal Web Apps, APIs)** | Medium | Reduce requests by 50% of the delta. Run load test. | Team Lead review. |
| **Tier-1 (Payment Gateway, Core DBs)** | High | Conduct load tests. Adjust limits only if CPU throttling is 0%. | SRE + Director approval. |

---

## 3. Create the Workload Optimization Plan
Draft an action plan based on the audit:

### Example Audit Findings:
*   **Target 1**: `default/legacy-billing-service` (10 replicas) is wasting **$2,099.48/mo**.
    *   *Action*: Apply VPA-recommended requests (`250m` CPU, `256Mi` RAM) and configure HPA.
*   **Target 2**: `kube-system/monitoring` is running on expensive On-Demand nodes.
    *   *Action*: Move Prometheus PV storage to gp3 and run metrics agents on ARM64 nodes.
*   **Target 3**: Namespace `staging` runs at full capacity overnight.
    *   *Action*: Apply Cron scale-down to 0 replicas between 8:00 PM and 8:00 AM.

---

## 4. Execute and Validate Savings
Apply the optimizations, wait 24 hours, and run the savings analysis query:

```promql
# Compare pre-optimization spend with post-optimization spend
sum(node_cpu_hourly_cost) + sum(node_ram_gb_hourly_cost * (node_memory_working_set_bytes / 1024 / 1024 / 1024))
```

Verify that:
1. Total cluster cost has decreased (e.g., node count dropped by 30%).
2. Application latency (p95/p99) has not degraded.
3. No OOMKills have occurred in optimized namespaces.
