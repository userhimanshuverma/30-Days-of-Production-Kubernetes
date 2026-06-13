# 🚀 Production Node Placement & Scheduling Strategies

Operating large-scale Kubernetes clusters in production requires careful planning of workload placement to control costs, guarantee high availability, and prevent resource fragmentation.

---

## 🧩 1. The Resource Fragmentation Problem

Resource fragmentation occurs when CPU or Memory allocations are scattered unevenly across nodes, leaving small pockets of unreservable space.

### ⚠️ The Scenario:
* You have 3 nodes, each with **2 CPU** and **4Gi Memory** remaining.
* Total cluster capacity: **6 CPU** and **12Gi Memory**.
* An incoming Pod requests **3 CPU** and **6Gi Memory**.
* **Result**: The Pod is marked `Pending` because no single node can fit the request, despite the cluster having ample total capacity.

### 🛡️ Production mitigations:
1. **Standardize Pod Sizes**: Align CPU/Memory request ratios. If all pods request multiples of standard building blocks (e.g., 0.5 CPU / 1Gi Mem), fragmentation is minimized.
2. **Implement Bin Packing**: Run custom scheduling profiles with the `NodeResourcesFit` plugin configured with `scoringStrategy.type: MostAllocated` to fill up nodes before scheduling to new ones.
3. **Use the Descheduler**: Periodically evict pods from underutilized or highly fragmented nodes so they can be rescheduled onto other nodes, allowing empty nodes to be scaled down.

---

## ⚖️ 2. Bin Packing vs. Spreading Trade-offs

| Strategy | Advantages | Disadvantages | Use Case |
|---|---|---|---|
| **Bin Packing** (`MostAllocated`) | High density, minimizes active nodes, enables aggressive cluster downscaling, saves up to 40% in cloud compute costs. | High blast radius if a node crashes, performance bottlenecks due to shared CPU caches, risk of CPU starvation. | Batch jobs, dev/staging environments, non-critical stateless workloads. |
| **Spreading** (`LeastAllocated`) | Maximizes performance, distributes CPU load, minimizes blast radius (one node outage only drops a small fraction of instances). | High cost, keeps many nodes partially running, limits effectiveness of Cluster Autoscalers. | Critical web APIs, transactional databases, production user-facing microservices. |

---

## 🛠️ 3. Dedicated Node Pools & GPU Routing

For specialized hardware (e.g. NVIDIA GPUs) or license-restricted workloads (e.g. Windows nodes), enforce isolation using a **combination of Taints and Node Affinity**:

> [!WARNING]
> **A common production anti-pattern**: Only using a toleration to route GPU workloads. If you taint a GPU node with `hardware=gpu:NoSchedule` and tolerate it on your pod, the pod *can* schedule there, but the scheduler is also free to schedule it onto a general CPU worker node. To guarantee it lands on a GPU node, you **must specify Node Affinity** in tandem.

```yaml
spec:
  tolerations:
  - key: "hardware"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: hardware
            operator: In
            values:
            - gpu
```

---

## 📉 4. Large-Scale Scheduling Optimization

When scaling past 1,000 nodes, the scheduler's latency can increase. Optimize with these parameters:

### 4.1 `percentageOfNodesToScore`
By default, the scheduler evaluates all nodes. In large clusters, this is too slow. The scheduler uses `percentageOfNodesToScore` to limit the number of feasible nodes it scores.
* Default: 50% for 100 nodes, scales down to 5% for clusters above 3,000 nodes.
* **Tuning**: Lowering this value (e.g., to 3% in a 5,000-node cluster) speeds up scheduling but may result in slightly sub-optimal placement decisions.

### 4.2 Pod Disruption Budgets (PDB) & Eviction Limits
When doing cluster upgrades, a node drain evicts pods. If PDBs are configured aggressively (e.g., `maxUnavailable: 0` or `minAvailable: 100%`), the drain will hang indefinitely. Always configure PDBs to allow at least 1 pod to be terminated at a time during maintenance windows.
