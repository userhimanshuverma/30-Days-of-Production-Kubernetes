# 📖 Kubernetes Resource Management: Inner Mechanics

This document provides a deep dive into how the Linux kernel enforces CPU and Memory resource constraints defined in your Kubernetes Pod specs.

---

## 1. CPU Requests vs. Limits: CFS Shares vs. Quotas

In Linux cgroups, CPU resources are managed differently depending on whether you configure **Requests** or **Limits**.

### CPU Requests = CFS Shares (`cpu.shares`)
*   **Linux Mechanism**: `cpu.shares` (Completely Fair Scheduler shares).
*   **How it works**: CPU requests are translated into relative shares. For example:
    *   Container A: `cpu: 1000m` -> 1024 shares.
    *   Container B: `cpu: 500m` -> 512 shares.
*   **Behavior**: Shares are **non-limiting**. If Container A is idle, Container B can consume 100% of the node's CPU. However, if both containers experience heavy load simultaneously, the kernel guarantees Container A receives twice as much CPU time as Container B.
*   **Analogy**: A cooperative workspace where desks are shared, but your reservation guarantees you get a desk during peak hours.

### CPU Limits = CFS Quotas (`cpu.cfs_quota_us` & `cpu.cfs_period_us`)
*   **Linux Mechanism**: CFS Bandwidth Control (`cpu.cfs_quota_us` / `cpu.cfs_period_us`).
*   **How it works**: Limits restrict a container's absolute CPU time within a fixed period (default period is 100,000 microseconds, or 100ms).
    *   Limit: `cpu: 200m` (0.2 cores).
    *   Formula: `quota = period * core_limit` -> `100ms * 0.2` = `20ms`.
    *   **Throttling**: The container can only consume a cumulative total of **20ms** of CPU time across all threads within each 100ms period. If the threads consume 20ms in the first 10ms of the period, the container is **throttled** (frozen) for the remaining 90ms.
*   **Impact**: Even if the host node has 90% idle CPU capacity, the kernel will forcefully throttle a container that exceeds its CFS quota. This causes severe latency spikes in multi-threaded application servers (like Java JVM, Node.js, Go).

---

## 2. Memory Requests vs. Limits: Cgroups & OOM Killing

Unlike CPU (which is a compressible resource that can be throttled), Memory is a **non-compressible resource**. If memory is exhausted, the OS must terminate processes to prevent a kernel crash.

```
                    [Memory Usage Increases]
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
   (Hits Memory Request)                 (Hits Memory Limit)
            │                                     │
   [Node Memory Pressure]                 [Cgroup OOM Triggered]
            │                                     │
    Is Node Low on RAM?                           │
     ┌──────┴──────┐                              │
     ▼             ▼                              ▼
 [No Event]   [Eviction Triggered]          [OOM-Killer kills Pod]
              (Kubelet restarts pod)        (Kernel terminates container)
                                            (Exit Code: 137)
```

### Memory Requests
*   **Linux Mechanism**: `memory.soft_limit_in_bytes` (not actively enforced by Kubernetes anymore; used primarily for scheduling).
*   **Kubelet Behavior**: Kubelet uses Memory Requests to bind pods to nodes. If a node runs out of physical memory (Node Memory Pressure), Kubelet looks at the pods whose usage exceeds their requested memory. These pods are prioritized for **Eviction** (shutdown and rescheduled elsewhere).

### Memory Limits
*   **Linux Mechanism**: `memory.limit_in_bytes`.
*   **Kernel Behavior**: The container runtime configures the hard limit on the cgroup. If the processes inside the container attempt to allocate RAM beyond this limit, the Linux kernel **Out-of-Memory (OOM) Killer** is invoked.
*   **Exit Code 137**: The kernel sends a `SIGKILL` (signal 9) directly to the process. In kubectl, this manifests as `OOMKilled` (Exit Code 137).

### OOM Score Adjustment (`oom_score_adj`)
The kernel assigns an `oom_score` (from 0 to 1000) to processes to determine which one to kill first during memory starvation. Kubelet configures this adjustment based on the Pod's **Quality of Service (QoS)** class:

| QoS Class | Resource Configuration | `oom_score_adj` | OOM Priority |
|---|---|---|---|
| **Guaranteed** | Requests == Limits for CPU & RAM | `-997` | **Last to be killed** (Highly protected) |
| **Burstable** | Requests != Limits (Some requests set) | `1000 - (10 * requestRatio)` | Killed based on ratio of usage to request |
| **BestEffort** | No requests or limits configured | `1000` | **First to be killed** |
