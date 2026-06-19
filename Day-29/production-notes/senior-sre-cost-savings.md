# 📓 Senior SRE Production Notes: Lessons in Platform Efficiency

This document captures lessons learned, real-world case studies, and anti-patterns observed while operating Kubernetes clusters containing thousands of nodes at tech scale (Netflix, Airbnb, AWS).

---

## 1. Top Cost Anti-Patterns in Kubernetes

### Anti-Pattern 1: "Request-Limit Equality"
*   **The Mistake**: Setting CPU Requests equal to CPU Limits (e.g., `requests.cpu: 4`, `limits.cpu: 4`).
*   **Why it's bad**: Developers do this to ensure their app performs well under peak loads. However, because the scheduler reserves the full **Request** size, the node's CPU capacity is locked up, even if the app's average usage is only 100m. This creates huge "slack" and forces the cluster to scale up nodes needlessly.
*   **SRE Rule**: Maintain a limit-to-request ratio (e.g., CPU Limits = 1.5x - 3x CPU Requests). For memory, keep limits closer to requests (1.2x - 1.5x) to handle OOM risks, but never set requests excessively high.

### Anti-Pattern 2: The "HPA-VPA Conflict Loop"
*   **The Mistake**: Running HPA (Horizontal Pod Autoscaler) and VPA (Vertical Pod Autoscaler) on the same CPU or Memory metric concurrently.
*   **Why it's bad**:
    1. CPU spikes -> HPA creates more pods to lower CPU utilization.
    2. Concurrently, VPA sees the CPU spike and attempts to allocate more CPU to the existing pods.
    3. The two controllers compete, leading to pod eviction loops, resource thrashing, and cluster instability.
*   **SRE Rule**: Only run HPA and VPA on the same deployment if HPA scales on a custom metric (like HTTP request queue depth or Kafka lag) while VPA manages physical CPU/Memory requests.

---

## 2. Real-World Case Study: 40% Savings in 3 Weeks

### The Challenge
A SaaS e-commerce company noticed their Kubernetes AWS EKS bill surged to **$85,000/month** for a relatively simple microservice layout running 150 pods.

### The Audit Findings
1.  **Overprovisioned staging**: Staging environment ran 24/7 with requests identical to production, costing $25,000/mo.
2.  **No node consolidation**: AWS Cluster Autoscaler was configured, but nodes were highly fragmented (average CPU request utilization was 18%).
3.  **No Spot usage**: All workers ran on On-Demand instances.

### The Remediation Executed
1.  **Replaced Cluster Autoscaler with Karpenter**: Enabled node consolidation with `consolidationPolicy: WhenUnderutilized` and `consolidateAfter: 30s`.
2.  **Transitioned Staging and Workers to Spot Nodes**: Standardized Spot affinity on low-risk workloads (saving ~70% on compute cost).
3.  **Configured Off-Hours Scaling**: scaled staging to 0 replicas on nights and weekends.
4.  **Tuned Requests via VPA**: Ran VPA in recommendation mode to identify overprovisioned apps.

### The Financial Outcome
*   **Pre-Optimization Bill**: $85,000/month
*   **Post-Optimization Bill**: $49,300/month
*   **Total Savings**: **$35,700/month (42% Reduction)**
*   **Performance Impact**: 0% change in API response time (p95 remained at 12ms).

---

## 3. Spot Instance Risk Management

Spot instances are a game changer, but running them in production requires strict SRE guardrails:

1.  **The "Graceful Degradation" Principle**: If all spot capacity is reclaimed, the application must gracefully failover to On-Demand. Do not set Spot as a strict requirement (`requiredDuringScheduling...`) on core APIs; use **preferred** affinities.
2.  **Spot Diversification**: Do not limit node pools to a single instance family. AWS Spot capacity is segmented by instance type and Availability Zone. Requesting a mix (e.g., `m5.large`, `c5.large`, `t3.large`) minimizes the risk of a total capacity outage.
3.  **Run Stateful on On-Demand**: Never schedule Databases, Kafka Broker Nodes, or Elasticsearch nodes on Spot capacity. The 2-minute drain limit is insufficient to sync multi-gigabyte disks, leading to database corruption.
