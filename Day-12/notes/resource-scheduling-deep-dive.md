# 🧠 Deep-Dive: Resource Management & Scheduler Mechanics

Understanding resource management in Kubernetes requires looking past YAML configurations and down into the Linux kernel mechanics, specifically **Control Groups (cgroups)**, the **Completely Fair Scheduler (CFS)**, and memory management subsystems.

---

## 1. Kernel Mechanics: How cgroups Power Kubernetes Resources

Kubernetes does not enforce resource boundaries itself. Instead, the Kubelet instructs the container runtime (`containerd` or `cri-o`) to set up cgroups.

### cgroups v1 vs cgroups v2
The Linux kernel provides cgroups to restrict resource usage of process groups:
- **cgroups v1:** Uses a split hierarchy where each resource (CPU, Memory, I/O) is managed in a separate tree. This leads to synchronization challenges, especially between memory limits and block I/O writebacks.
- **cgroups v2:** Provides a unified hierarchy. All controllers are attached to a single process tree. This makes resource allocation much more predictable and allows features like **Memory High** (soft limit) and unified resource monitoring.

### CPU Request vs Limit Mechanics
In the Linux kernel, CPU is managed using two primary parameters:
1. **CPU Shares (`cpu.shares` in v1, `cpu.weight` in v2):** 
   - Proportional weight.
   - 1 CPU request = 1024 shares.
   - If a node with 2 CPUs has two containers running, one with 1024 shares (1 CPU requested) and another with 2048 shares (2 CPU requested), the CPU cycles will be split 1:2 *only during CPU contention*. If one container goes idle, the other can consume 100% of both CPUs.
2. **CFS Bandwidth Control (`cpu.cfs_quota_us` and `cpu.cfs_period_us`):**
   - hard limit.
   - `cpu.cfs_period_us` is the period, default is `100,000 microseconds` (100ms).
   - `cpu.cfs_quota_us` is the quota of runtime within that period.
   - A limit of 0.5 CPU translates to a quota of `50,000 microseconds` every 100ms. If a container uses `50ms` of CPU runtime in the first `10ms` (by utilizing multiple threads), it is throttled for the remaining `90ms` of that period.

### Memory Requests vs Limits
Unlike CPU, memory cannot be throttled or compressed.
1. **Memory Requests:**
   - Used by the scheduler to reserve memory on the node.
   - Translates to `memory.oom_control` adjustments and `memory.low` / `memory.min` settings in cgroups v2 to protect the container's memory working set from swap/eviction.
2. **Memory Limits:**
   - Translates to `memory.limit_in_bytes` (cgroups v1) or `memory.max` (cgroups v2).
   - Once a container's RSS (Resident Set Size) memory reaches this threshold, the kernel will attempt to reclaim page cache. If it cannot free enough memory, the kernel OOM killer fires immediately.

---

## 2. QoS Classification & Eviction Logic

When a node experiences resource starvation, the Kubelet must evict Pods to prevent node instability. It determines eviction candidacy via the **QoS Class** and **`oom_score_adj`**.

### QoS Class Mapping
Kubernetes dynamically assigns one of three QoS classes based on a Pod's resources block:

```yaml
# 1. GUARANTEED (requests == limits for all containers)
apiVersion: v1
kind: Pod
metadata:
  name: guaranteed-pod
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: "1"
        memory: "1Gi"
      limits:
        cpu: "1"
        memory: "1Gi"

# 2. BURSTABLE (requests < limits, or only some limits set)
apiVersion: v1
kind: Pod
metadata:
  name: burstable-pod
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
      limits:
        cpu: "1"
        memory: "1Gi"

# 3. BESTEFFORT (no requests or limits defined)
apiVersion: v1
kind: Pod
metadata:
  name: besteffort-pod
spec:
  containers:
  - name: app
    # No resources block defined
```

### Eviction Priority via `oom_score_adj`
Every process in Linux has an `oom_score` (between 0 and 1000) calculated by the kernel. The higher the score, the more likely the process is to be killed during an OOM event.
The Kubelet adjusts this score using the `oom_score_adj` setting on container processes:

| QoS Class | `oom_score_adj` Formula / Value | Description |
|---|---|---|
| **Guaranteed** | `-997` | Heavily protected. The system will kill almost any other process before touching this. |
| **BestEffort** | `1000` | Unprotected. These processes are always killed first during memory pressure. |
| **Burstable** | $$1000 - \max\left(\left(\frac{\text{Memory Request}}{\text{Node Capacity}} \times 1000\right), 2\right)$$ | Proportional protection. Pods with larger memory requests relative to node size get lower scores (higher protection). |

---

## 3. Kubernetes Scheduler: Internals & Algorithms

The `kube-scheduler` assigns pending Pods to nodes in a multi-step execution cycle.

```
+------------------------------------------------------------+
|                       Scheduling Queue                     |
+------------------------------┬-----------------------------+
                               │ (Dequeues Pod)
                               ▼
+------------------------------------------------------------+
|                        Filtering Phase                     |
|                                                            |
|  Evaluates Predicates:                                      |
|  - NodeResourcesFit (Checks CPU/Mem requests)              |
|  - NodeName (Checks direct node request)                    |
|  - PodTopologySpread (Spreads across zones)                |
|  - NodeAffinity & Taints/Tolerations                       |
+------------------------------┬-----------------------------+
                               │ (List of Feasible Nodes)
                               ▼
+------------------------------------------------------------+
|                         Scoring Phase                      |
|                                                            |
|  Evaluates Priority Functions (0-100 score):               |
|  - NodeResourcesFitScoring (Bin Packing vs Spread)         |
|  - ImageLocalityPriority (Checks if image exists)          |
|  - NodeAffinityPriority                                    |
+------------------------------┬-----------------------------+
                               │ (Selects Node with Max Score)
                               ▼
+------------------------------------------------------------+
|                         Binding Phase                      |
|                                                            |
|  Creates Binding Object -> Notifies API Server             |
+------------------------------------------------------------+
```

### Phase 1: Filtering (Predicates)
The scheduler filters out nodes that cannot run the Pod. It evaluates a set of **Predicates**:
- **NodeResourcesFit:** Does the node have enough unreserved CPU and Memory requests to satisfy the Pod?
- **PodTopologySpread:** Does placement violate topology spread constraints?
- **NodePorts:** Are the requested host ports already bound on the node?
- **TaintsAndTolerations:** Does the Pod tolerate the node's taints?
- **NodeAffinity/Selector:** Does the node match the Pod's node selector?

### Phase 2: Scoring (Priorities)
For the nodes that passed the filtering phase, the scheduler calculates a score between `0` and `100` using a set of **Priority Functions**:
- **NodeResourcesLeastAllocated / NodeResourcesMostAllocated:** Configures the scheduling strategy (Spread vs Bin Packing).
- **ImageLocality:** Scores nodes higher if they already have the container images cached locally.
- **NodeAffinityPriority:** Scores nodes based on preferred (soft) node affinity rules.
- **InterPodAffinityPriority:** Evaluates Pod affinity and anti-affinity scoring.

### Phase 3: Node Selection
The scheduler selects the node with the highest cumulative score. If there is a tie, it selects one at random. Finally, it creates a `Binding` object in the API Server, which triggers the target node's Kubelet to start the container.

---

## 4. Bin Packing: Real-world Trade-offs

Bin Packing optimizes cluster costs by grouping workloads together. Let's compare strategies:

### Spread (Default)
- **Scores nodes with less resource utilization higher.**
- **Formula:** 
  $$\text{Score} = \frac{\text{CPU Available}}{\text{CPU Capacity}} \times 50 + \frac{\text{Memory Available}}{\text{Memory Capacity}} \times 50$$
- **Pros:** Maximum performance isolation; zero risk of noisy neighbors.
- **Cons:** Very expensive. You will have many nodes running at 20-30% utilization, preventing cluster autoscalers from terminating nodes.

### Bin Packing (`NodeResourcesMostAllocated`)
- **Scores nodes with higher resource utilization higher.**
- **Formula:** 
  $$\text{Score} = \frac{\text{CPU Requested}}{\text{CPU Capacity}} \times 50 + \frac{\text{Memory Requested}}{\text{Memory Capacity}} \times 50$$
- **Pros:** Concentrates workloads onto fewer nodes. Empty nodes are freed, allowing the **Cluster Autoscaler** (or Karpenter) to terminate them, saving 30-50% on cloud bills.
- **Cons:** Highly packed nodes run the risk of memory fragmentation and higher scheduling latency due to tight fit requirements.
