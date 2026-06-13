# 🧠 Kubernetes Scheduler Internals Deep Dive

This document provides a low-level architectural analysis of the Kubernetes scheduler (`kube-scheduler`). It covers the queueing mechanisms, scheduling loop phases, and concurrency models used to match Pods to Nodes at scale.

---

## 🗂️ 1. The Multi-Queue Scheduler Cache

The scheduler maintains an in-memory cache of nodes and pods to avoid querying the `kube-apiserver` on every operation. The scheduler's queueing system is divided into three distinct queues:

```
                  [ Unscheduled Pods ]
                           │
                           ▼
                  ┌─────────────────┐
                  │   ActiveQueue   │◀───────────────┐
                  └─────────────────┘                │
                           │                         │
            (Pop Pod)      │                         │
                           ▼                         │ (Requeue Trigger)
                     [ Scheduling ]                  │
                           │                         │
             ┌─────────────┴─────────────┐           │
   Success   │                           │ Failure   │
   ┌─────────┘                           └─────────┐ │
   ▼                                               ▼ │
[ Binding ]                                   ┌─────────┐
                                              │BackoffQ │
                                              └─────────┘
                                                   ▲
                                                   │ (Event Trigger)
                                              ┌─────────┐
                                              │UnschedQ │
                                              └─────────┘
```

### 1.1 `ActiveQ` (Active Queue)
A priority queue (heap) sorted by Pod priority (using `PriorityClass`). The scheduler pulls the highest-priority pod from this queue to schedule.

### 1.2 `UnschedulablePods` (Unschedulable Pool)
If a Pod cannot be scheduled due to a hard constraint (e.g. no node has enough memory), it is placed in this pool. It stays here until a cluster event occurs that might make it schedulable (e.g., node resource updates, pod deletes, node label updates).

### 1.3 `PodBackoffQ` (Backoff Queue)
If scheduling fails due to a transient error, the Pod is placed in this queue. The backoff duration increases exponentially for each consecutive failure. Once the backoff duration expires, the Pod is moved back to the `ActiveQ`.

---

## 🔄 2. The Two-Cycle Execution Loop

The scheduler operates using two decoupled loops: the **Scheduling Cycle** (runs synchronously, one pod at a time) and the **Binding Cycle** (runs asynchronously, processing concurrent bindings).

```
   ┌─────────────────────────────────────────────────────────────┐
   │                  SCHEDULING CYCLE (Sync)                    │
   │                                                             │
   │  [Pop Pod] ──▶ [Filtering] ──▶ [Scoring] ──▶ [Reserving]   │
   └──────────────────────────────────────────────────────┬──────┘
                                                          │
                                                          ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                   BINDING CYCLE (Async)                     │
   │                                                             │
   │  [Permitting] ──▶ [Pre-Bind] ──▶ [Binding] ──▶ [Post-Bind]  │
   └─────────────────────────────────────────────────────────────┘
```

### 2.1 The Scheduling Cycle (Synchronous)
To prevent race conditions on node resources, the scheduling cycle runs on a single thread:

1. **Filtering (Predicates)**: Filters out nodes that do not satisfy the Pod's requirements. Evaluates plugins in parallel:
   * `NodeResourcesFit`: Compares Pod CPU/Memory requests against available node capacity.
   * `NodePorts`: Checks if the requested ports on the node host are already bound.
   * `NodeName`: Matches the `spec.nodeName` field.
   * `NodeAffinity`: Checks if the Node satisfies selector and affinity expressions.
   * `PodTopologySpread`: Inspects topology limits to avoid exceeding skew constraints.
2. **Scoring (Priorities)**: Ranks remaining nodes. Each plugin returns a score between 0 and 100:
   * `NodeResourcesBalancedAllocation`: Prefers nodes with balanced CPU and Memory utilization (aiming to match ratio of requested CPU to Memory).
   * `ImageLocality`: Scores nodes higher if they already have the container images cached.
   * `NodeAffinityPriority`: Ranks nodes based on soft node affinity weights.
3. **Reserving**: The scheduler updates its local cache (optimistically reserving resources on the selected node) before sending the binding request to the API Server. This allows the single thread to immediately start scheduling the next Pod without waiting for a network database write.

### 2.2 The Binding Cycle (Asynchronous)
Once a node is reserved, the binding cycle runs on a separate goroutine:

1. **Permitting**: Evaluates `Permit` plugins, which can hold a pod's binding. This is critical for **Batch Scheduling** (e.g., waiting for all worker pods of a spark job to be ready before starting any).
2. **Pre-Bind**: Performs volume mounting or host configuration.
3. **Binding**: Sends a `Binding` API request to `kube-apiserver`. The API server writes `spec.nodeName: <node-name>` to etcd.
4. **Post-Bind**: Cleans up resources or records success metrics.

---

## ⚡ 3. Preemption and Eviction Mechanics

When a high-priority Pod cannot find a node, the scheduler executes **Preemption**:

1. **Victim Searching**: The scheduler scans the cluster to find a node where evicting one or more lower-priority Pods would make enough room for the high-priority Pod.
2. **Preemption Nomination**: The scheduler sets `spec.nominatingNodeName` on the high-priority Pod.
3. **Victim Eviction**: The scheduler deletes the victim pods, triggering standard termination routines.
4. **Rescheduling**: Once the node resources are free, the scheduler places the high-priority Pod on the nominated node.
