# 🛡️ Platform Engineering Notes: Lessons Learned from Large-Scale Scheduling

Operating Kubernetes at scale exposes the limitations of default configurations. This document outlines lessons learned from running large multi-tenant production clusters.

---

## 1. The CPU Limit Controversy: To Limit or Not to Limit?

In theory, setting CPU limits protects the host from runaway CPU usage. In practice, setting CPU limits on latency-sensitive APIs often causes severe performance issues.

### The CFS Throttling Trap
Kubernetes uses the **Completely Fair Scheduler (CFS) quota** mechanism to enforce CPU limits. Under load:
- A container running multi-threaded workloads (like Java, Node.js, Go) can exhaust its 100ms CFS quota in the first 20-30ms of a period.
- Even if average CPU usage is at 20%, the container is throttled for the remaining 70-80ms of the period, resulting in **p99 latency spikes** of hundreds of milliseconds.
- **Solution:** For low-latency microservices, many platform teams **omit CPU limits** entirely (keeping only CPU requests) and control noisy neighbors at the node level using priority classes, or utilize the `CPUManager` policy to allocate dedicated CPU cores (Static Policy).

---

## 2. Resource Fragmentation & Bin Packing Trade-offs

A cluster can have plenty of spare CPU and Memory capacity in aggregate, yet still fail to schedule a Pod. This is **Resource Fragmentation**.

```
                Node 1: 1.5 CPU Free
                Node 2: 1.5 CPU Free
                Node 3: 1.5 CPU Free
                
                Total Cluster Capacity Free: 4.5 CPU
                
                Incoming Pod Request: 2.0 CPU
                Result: FAILED TO SCHEDULE (No single node fits!)
```

### Minimizing Fragmentation
1. **Standardize Node Sizes:** Avoid having a wide variety of instance sizes in the same node pool. Stick to a standard size (e.g. `c6i.4xlarge`) to make packing math predictable.
2. **Use Bin Packing:** Adjust the scheduler config to use `NodeResourcesMostAllocated`. This packs Pods tightly, leaving entire nodes completely free to be scale-down targets.
3. **Beware the Trade-off:** Dense packing increases the blast radius of host failures. If a packed node fails, many Pods are terminated simultaneously, causing traffic spikes on the remaining nodes.

---

## 3. Overcommit Strategies for Memory

Unlike CPU, memory cannot be overcommitted without risk.
- **Do NOT overcommit Memory on critical workloads.** Always set memory Request == Limit (Guaranteed QoS).
- For Dev/Staging environments, you can overcommit memory by setting Limits > Requests. However, you must configure the Kubelet eviction thresholds:
  ```bash
  --eviction-hard=memory.available<500Mi,nodefs.available<10%
  ```
  This instructs Kubelet to preemptively evict BestEffort and Burstable workloads *before* a system OOM killer crashes the host.

---

## 4. Noisy Neighbors and Priority Preemption

Without isolation policies, a batch processing job can starve your billing API.
- Use **PriorityClasses** to mark critical APIs as high priority:
  ```yaml
  apiVersion: scheduling.k8s.io/v1
  kind: PriorityClass
  metadata:
    name: high-priority-api
  value: 1000000
  globalDefault: false
  description: "Use this class for critical user-facing microservices."
  ```
- If the node runs out of space, the scheduler will preempt (evict) lower-priority pods (like background workers) to accommodate the `high-priority-api` Pod.

---

## 5. Large Cluster Scheduling Bottlenecks

As clusters grow past 500 nodes and 10,000 Pods, the scheduling queue can become a bottleneck.
- **`percentageOfNodesToScore`:** By default, the scheduler scores all nodes in the cluster. For large clusters, configure the scheduler to stop searching once a certain percentage of nodes have been found (e.g., set to `10` or `20` for a 1000-node cluster).
- **Karpenter vs Cluster Autoscaler:** For large-scale dynamic capacity provisioning, replace the default Cluster Autoscaler with **Karpenter**. Karpenter schedules and provisions nodes in seconds by directly calling cloud APIs, bypassing the slow ASG-based scaling cycles.
