# 🚀 Autoscaling Efficiency & Overprovisioning Playbook

This playbook outlines advanced configurations to align Horizontal Pod Autoscaling (HPA) and node provisioning (Karpenter) to achieve rapid scaling response times without wasting idle cluster resources.

---

## 1. HPA and Karpenter Coordination

When traffic spikes occur:
1. **HPA detects load**: Scales up replicas in the Deployment.
2. **Pods fail to schedule**: Due to insufficient CPU/RAM on existing nodes, pods are marked `PENDING`.
3. **Karpenter reacts**: Intercepts the `PENDING` pods, calculates the optimal instance types needed, and calls cloud APIs to launch nodes.
4. **Node joins cluster**: Pods bind and start running.

```
Traffic Spike ──> HPA scales Pods ──> Pods PENDING ──> Karpenter provisions Node ──> Pods scheduled
                                                                                   (Takes 45s - 3m)
```

The time from step 2 to step 4 represents a **latency window** where traffic is queueing or failing because nodes are booting. To optimize this, we must configure:
*   **HPA stabilization behaviors**.
*   **Cluster Overprovisioning (Buffer Pods)**.

---

## 2. Preventing Scaling Thrashing

"Thrashing" occurs when a cluster rapidly scales up and down in response to transient CPU spikes, leading to waste, high node spin-up/down costs, and instability.

### Optimizing HPA Cooldowns (`behavior` block)
Configure HPA behavior to scale up immediately, but scale down gradually using a stabilization window:

```yaml
spec:
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0 # React instantly to traffic bursts
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15 # Double capacity if necessary
    scaleDown:
      stabilizationWindowSeconds: 300 # Wait 5 minutes before scaling down to absorb subsequent traffic waves
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60 # Scale down slowly, max 10% reduction per minute
```

---

## 3. Cluster Overprovisioning (Pre-Warming Nodes)

If an application requires sub-10 second scaling times, waiting for Karpenter to spin up virtual VMs (which takes 45–90 seconds) is unacceptable. 

We solve this using **Cluster Overprovisioning**—allocating placeholder pods that do nothing but occupy space.

```
[Node Capacity] ───────────────┐
│ [Active Pod]  [Active Pod]   │
│ [Active Pod]  [Pause Pod]    │  <-- Occupies space at Priority: -10
└──────────────────────────────┘
               │ (New Active Pod schedules immediately)
               ▼
[Node Capacity] ───────────────┐
│ [Active Pod]  [Active Pod]   │
│ [Active Pod]  [Active Pod]   │  <-- Kick out Pause Pod to PENDING
└──────────────────────────────┘
               │ (Karpenter spins up new node in background for Pause Pod)
               ▼
[New Node Capacity] ───────────┐
│ [Pause Pod]  [Idle Space]    │
└──────────────────────────────┘
```

### Implementation Steps

#### Step 1: Create a Low-Priority PriorityClass
Create a `PriorityClass` with a negative value. Normal workloads run at `value: 0` or higher (e.g., `1000000` for system pods), meaning Kubernetes will evict our placeholder pods to make room.

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: overprovisioning-priority
value: -10 # Lower than any standard application pod
globalDefault: false
description: "Used by pause pods to reserve cluster capacity. Evicted immediately when actual workloads schedule."
```

#### Step 2: Deploy the Overprovisioning Daemon/Deployment
Deploy a placeholder deployment using the Google `pause` container. The CPU/RAM requests of these pause pods act as the "capacity buffer".

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-overprovisioner
  namespace: kube-system
spec:
  replicas: 4 # Maintain a pool of 4 warm node placeholders
  selector:
    matchLabels:
      app: cluster-overprovisioner
  template:
    metadata:
      labels:
        app: cluster-overprovisioner
    spec:
      priorityClassName: overprovisioning-priority
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
        resources:
          # Size the request to match the typical instance shape
          # e.g., if nodes are 8 Cores / 32Gi, requesting 7 Cores reserves almost a full node
          requests:
            cpu: "2"
            memory: 8Gi
```

---

## 4. Karpenter Node Consolidation

Karpenter consolidates nodes to minimize costs when workloads terminate or shrink.

*   `consolidationPolicy: WhenUnderutilized`: Karpenter constantly monitors nodes. If it can move all pods running on Node A onto Node B (and node C) to terminate Node A, it will automatically orchestrate the node drain.
*   `consolidationPolicy: WhenEmpty`: Karpenter only decommissions a node if all workloads are terminated and it is empty.

For production, **`WhenUnderutilized`** is highly recommended as it drives massive cost reductions by keeping cluster bin packing highly compressed.
```yaml
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
```
> [!TIP]
> To prevent specific critical pods (e.g., active database migrations, stateful jobs) from being terminated during consolidation, add the following annotation to the pod:
> `karpenter.sh/do-not-disrupt: "true"`
