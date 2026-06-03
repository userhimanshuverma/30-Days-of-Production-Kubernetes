# 🛡️ Day 12: Resource Management & Scheduling
### 🏷️ PHASE 2 — RUNNING REAL APPLICATIONS

Welcome to Day 12. Today, we dive into the heart of Kubernetes platform engineering: **Resource Management and scheduling behavior**. 

Operating a multi-tenant Kubernetes cluster without a deep, mechanical understanding of how resources are allocated, limited, and scheduled is like flying a jet with no instrument panel. Sooner or later, you will encounter CPU starvation, OOM kills, noisy neighbors, and fragmented nodes.

This guide is designed to make you an expert in resource configuration and scheduler mechanics, so you will never again have to ask:
> *"Why did Kubernetes schedule my Pod on that node?"* or *"Why did my application randomly get restarted with Exit Code 137?"*

---

## 🗺️ Day 12 Directory Structure

Here is how the learning resources for today are structured:
- [notes/resource-scheduling-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-12/notes/resource-scheduling-deep-dive.md) — Comprehensive technical theory (Linux cgroups, Scheduler filtering/scoring).
- [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-12/diagrams/) — 12 professional architecture, workflow, and lifecycle diagrams.
- [labs/](file:///d:/30_Days_of_Production_Kubernetes/Day-12/labs/) — Four production-focused hands-on labs (QoS, OOM, scheduling diagnostics, and bin packing).
- [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-12/manifests/) — Production-ready YAML manifests used in the labs.
- [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-12/production-notes/lessons-learned.md) — Platform engineering insights, sizing guides, and overcommit strategies.
- [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-12/troubleshooting/playbook.md) — Standard operating procedures for CPU throttling, OOMKilled, and FailedScheduling.
- [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-12/exercises/challenges.md) — Real-world scenarios to test your optimization and debugging skills.
- [resources/kubernetes-scheduler-lab.html](file:///d:/30_Days_of_Production_Kubernetes/Day-12/resources/kubernetes-scheduler-lab.html) — Futuristic, interactive, single-page HTML simulator to experiment with scheduling, bin packing, scoring, and evictions.

---

## 1. Why Resource Management Matters

In a production cluster, Kubernetes abstracts physical or virtual hardware into a unified pool of compute. Without proper resource constraints, this abstraction crumbles due to three core realities:

```
┌────────────────────────────────────────────────────────┐
│                   Shared Infrastructure                │
│  ┌──────────────────┐ ┌──────────────────┐ ┌─────────┐  │
│  │   Pod A (Noisy)  │ │   Pod B (Quiet)  │ │ Kubelet │  │
│  │  Consumes 95% CPU│ │  Starved of CPU  │ │ Hangs   │  │
│  └─────────┬────────┘ └────────┬─────────┘ └────┬────┘  │
└────────────┼───────────────────┼────────────────┼───────┘
             ▼                   ▼                ▼
 ────────────┴───────────────────┴────────────────┴────────
                       Underlying Linux Kernel
 ──────────────────────────────────────────────────────────
```

### Shared Infrastructure
Nodes run multiple workloads from different namespaces, business units, and criticality levels. Kubernetes relies on Linux Kernel resource isolation (cgroups and namespaces) to keep these workloads sandboxed. If a Pod is allowed to consume resources boundlessly, it can degrade the host, crashing the Kubelet or other critical daemons.

### Resource Contention (The "Noisy Neighbor")
If Pod A experiences a sudden traffic spike and has no resource limits, it will attempt to consume all available CPU and Memory on the node. As a result:
- **Pod B** (running on the same node) is starved of CPU cycles, causing latency spikes and timed-out requests.
- **Node-level services** (Kubelet, Container Runtime, Log Forwarders) cannot execute, rendering the node unhealthy.

### Multi-Tenant Clusters
In multi-tenant setups, resource management is the mechanism of policy enforcement. Resource quotas and limit ranges ensure that one team's dev namespace cannot consume the entire budget of the cluster, leaving nothing for production deployments.

---

## 2. CPU & Memory Requests

### Scheduling Decisions
When a Pod is submitted to the API server, the `kube-scheduler` looks at the Pod's **Requests**, not its Limits, and not its actual runtime usage. 
- **A Request is a reservation.** If a Pod requests `2 CPU` and `4Gi` of Memory, the scheduler guarantees that the target node has at least that much *unreserved* capacity.
- The scheduler maintains an internal ledger of how much capacity is reserved on each node. 
  $$\text{Allocatable Capacity} - \sum(\text{Requests of Scheduled Pods}) = \text{Available for Scheduling}$$

### Guaranteed Resources
Once scheduled, the CPU Request is translated by the Kubelet into Linux `cpu.shares` (a proportional CPU weight). If the node experiences CPU contention, the kernel guarantees that the container will receive CPU cycles proportional to its request.
- **CPU** is a **compressible resource**. If requests are exceeded, the kernel throttles the container (slows down execution) but does not terminate it.
- **Memory** is an **incompressible resource**. You cannot throttle memory. If the node runs out of physical memory, the Linux kernel Out-Of-Memory (OOM) Killer must terminate a process to prevent a complete kernel panic.

---

## 3. Resource Limits

While requests represent the *minimum guaranteed reservation*, **Limits** represent the *hard ceiling* that a container is allowed to consume.

```
                  ┌───────────────────────────────┐
                  │          MEMORY LIMIT         │ ──► Exceeding this triggers OOMKilled
                  ├───────────────────────────────┤     (Immediate Process Termination)
                  │                               │
                  │                               │
                  ├───────────────────────────────┤
                  │           CPU LIMIT           │ ──► Exceeding this triggers Throttling
                  ├───────────────────────────────┤     (CFS scheduler restricts CPU cycles)
                  │                               │
                  │          CPU REQUEST          │ ──► Guaranteed minimum share
                  └───────────────────────────────┘
```

### Enforcement Mechanics
Kubelet configures the container runtime (e.g., `containerd`) to write limits into the container's cgroup directory on the host:
- **Memory Limits** are written to `memory.limit_in_bytes` (cgroups v1) or `memory.max` (cgroups v2).
- **CPU Limits** are written to `cpu.cfs_quota_us` and `cpu.cfs_period_us`.

### CPU Throttling
Kubernetes uses the **Completely Fair Scheduler (CFS) bandwidth control** to enforce CPU limits. It operates on a default 100ms period (`cfs_period_us`).
- If a container has a limit of `2 CPU` (which translates to `200ms` of CPU runtime per `100ms` period), and it exhausts its 200ms quota in the first 20ms of the period, the kernel **throttles** the container's processes for the remaining 80ms.
- **Production Implication:** High CPU throttling causes severe latency tails ($p99$ and $p99.9$ spikes) in HTTP APIs, even when average CPU utilization looks low.

### OOMKilled Scenarios (Exit Code 137)
If a container attempts to allocate memory beyond its configured memory limit, the container runtime blocks the allocation. If the container cannot free memory, the Linux OOM Killer intervenes, reads the container's cgroup, selects the process, and sends a `SIGKILL` (Exit Code 137).
- Unlike CPU, there is no throttling for memory. **OOM is immediate and destructive.**
- OOM kills can also happen at the **Node level** (System OOM) if the node runs out of physical memory due to overcommitted burstable Pods. In this case, the Kubelet evicts Pods based on their Quality of Service (QoS) class and resource usage.

---

## 4. Quality of Service (QoS) Classes

Kubernetes classifies Pods into three QoS classes based on how their requests and limits are defined. This classification is done automatically by the Kubelet at scheduling time and dictates eviction priority during resource starvation.

| QoS Class | Resource Definition | Eviction Priority (OOM Score Adj) | Typical Workloads |
|---|---|---|---|
| **Guaranteed** | Requests == Limits for *both* CPU and Memory (across all containers in Pod). | Lowest (`-997`) | Production Databases, Kafka, Core Ingress Controllers |
| **Burstable** | Requests < Limits, or requests are configured but limits are not. | Medium (`2` to `999` based on request % of node capacity) | Web APIs, Microservices, Background Workers |
| **BestEffort** | No Requests and no Limits configured. | Highest (`1000`) | Non-critical batch jobs, CI/CD runners, dev scrapers |

### Eviction Priorities & Production Implications
When a node runs low on memory (e.g., node available memory drops below `100Mi` threshold), the Kubelet initiates Pod eviction to protect the host:
1. **BestEffort Pods** are evicted first.
2. **Burstable Pods** are evicted next, starting with the Pod that is consuming the highest percentage of memory relative to its request.
3. **Guaranteed Pods** are only evicted as a last resort, when system daemons (`kubelet`, `docker`/`containerd`) are in danger of crashing.

---

## 5. Scheduler Deep Dive

The `kube-scheduler` is a highly optimized, loop-driven component that assigns unbound Pods to nodes. For each Pod, the scheduling cycle runs in three main phases:

```
                    ┌─────────────────────────┐
                    │      Unbound Pod        │
                    └────────────┬────────────┘
                                 │
                                 ▼
                     Phase 1: FILTERING (Predicates)
                     [Node Fit, Taints, Ports, etc.]
                                 │
                                 ▼
                     Phase 2: SCORING (Priorities)
                     [Bin Packing, Affinity, Locality]
                                 │
                                 ▼
                     Phase 3: BINDING
                     [Write binding to API Server]
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │    Pod Bound to Node    │
                    └─────────────────────────┘
```

### 1. Filtering Phase (Predicates)
The scheduler filters out nodes that cannot run the Pod. It evaluates a set of **Predicates**:
- **NodeResourcesFit:** Does the node have enough unreserved CPU and Memory requests to satisfy the Pod?
- **PodTopologySpread:** Does placement violate topology spread constraints?
- **NodePorts:** Are the requested host ports already bound on the node?
- **TaintsAndTolerations:** Does the Pod tolerate the node's taints?
- **NodeAffinity/Selector:** Does the node match the Pod's node selector?

### 2. Scoring Phase (Priorities)
For the nodes that passed the filtering phase, the scheduler calculates a score between `0` and `100` using a set of **Priority Functions**:
- **NodeResourcesLeastAllocated / NodeResourcesMostAllocated:** Configures the scheduling strategy (Spread vs Bin Packing).
- **ImageLocality:** Scores nodes higher if they already have the container images cached locally.
- **NodeAffinityPriority:** Scores nodes based on preferred (soft) node affinity rules.
- **InterPodAffinityPriority:** Evaluates Pod affinity and anti-affinity scoring.

### 3. Node Selection
The scheduler selects the node with the highest cumulative score. If there is a tie, it selects one at random. Finally, it creates a `Binding` object in the API Server, which triggers the target node's Kubelet to start the container.

---

## 6. Bin Packing

Platform teams must choose between two opposing scoring strategies for cluster resource utilization:

### Strategy 1: Least Allocated (Spread)
- **Goal:** Distribute Pods evenly across all nodes to minimize resource contention.
- **Formula:** Node score is proportional to available capacity:
  $$\text{Score} = \frac{\text{Capacity} - \text{Requested}}{\text{Capacity}} \times 100$$
- **Trade-off:** Very safe for performance, but extremely expensive. Nodes run at low utilization (e.g., 30%), preventing autoscalers from scaling down nodes.

### Strategy 2: Most Allocated (Bin Packing)
- **Goal:** Pack Pods densely onto as few nodes as possible to allow empty nodes to be terminated by the cluster autoscaler.
- **Formula:** Node score is proportional to allocated capacity:
  $$\text{Score} = \frac{\text{Requested}}{\text{Capacity}} \times 100$$
- **Trade-off:** Maximizes cluster efficiency and reduces cloud costs by up to 50%. However, it increases the risk of resource contention if limits are not set correctly.

---

## 7. Production Examples

Here is how you should structure resource configurations for common production workloads:

### API Workloads (Low Latency, High Throughput)
APIs are sensitive to CPU throttling (causes p99 latency spikes).
- **QoS:** Burstable (to allow spikes) or Guaranteed (for critical APIs).
- **Recommendation:** Keep CPU requests close to average usage, but allow limits to go higher, OR set CPU requests equal to limits if performance consistency is paramount.
```yaml
resources:
  requests:
    cpu: "2"
    memory: "4Gi"
  limits:
    cpu: "4"         # Set CPU limit higher to handle spikes, or omit to avoid throttling
    memory: "4Gi"     # Memory request == limit to avoid OOM termination of the API process
```

### Relational Databases (Stateful PostgreSQL/MySQL)
Databases must NEVER be OOM-killed. Data corruption can occur if the database is abruptly terminated during a transaction write.
- **QoS:** Guaranteed.
```yaml
resources:
  requests:
    cpu: "8"
    memory: "32Gi"
  limits:
    cpu: "8"
    memory: "32Gi"   # Guaranteed QoS ensures lowest OOM score (-997)
```

### Kafka Brokers (Heavy IO, Page Cache Reliance)
Kafka relies heavily on the Linux Page Cache (unallocated memory) for disk caching.
- **QoS:** Guaranteed.
- **Note:** Ensure JVM heap is set to 50-60% of the memory limit, leaving the rest of the memory for the OS Page Cache.
```yaml
resources:
  requests:
    cpu: "4"
    memory: "16Gi"
  limits:
    cpu: "4"
    memory: "16Gi"
```

### Machine Learning Workloads (GPU and Heavy CPU/Memory)
ML training workloads require dedicated GPU resources and large amounts of system memory.
- **QoS:** Guaranteed.
```yaml
resources:
  requests:
    cpu: "16"
    memory: "64Gi"
    nvidia.com/gpu: "1"
  limits:
    cpu: "16"
    memory: "64Gi"
    nvidia.com/gpu: "1"
```

### Apache Pinot / ClickHouse (Analytical Database)
Real-time analytical databases have massive memory requirements and utilize JVM off-heap allocations.
- **QoS:** Guaranteed.
```yaml
resources:
  requests:
    cpu: "16"
    memory: "64Gi"
  limits:
    cpu: "16"
    memory: "64Gi"
```

---

## 🏁 Summary of Daily Tasks

To complete Day 12, execute the following steps in order:
1. **Understand Scheduler Mechanics:** Read the [Deep Dive Notes](file:///d:/30_Days_of_Production_Kubernetes/Day-12/notes/resource-scheduling-deep-dive.md) and review the [Diagrams](file:///d:/30_Days_of_Production_Kubernetes/Day-12/diagrams/).
2. **Interactive Simulation:** Open the [Scheduler Lab Simulator](file:///d:/30_Days_of_Production_Kubernetes/Day-12/resources/kubernetes-scheduler-lab.html) in your browser and practice scheduling Pods under different constraints.
3. **Hands-on Labs:** Complete [Lab 1 through Lab 4](file:///d:/30_Days_of_Production_Kubernetes/Day-12/labs/) in a local development cluster (Kind/Minikube).
4. **Complete Exercises:** Solve the production sizing and debugging scenarios in [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-12/exercises/challenges.md).
