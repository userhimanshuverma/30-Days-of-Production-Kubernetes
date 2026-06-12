# 🏆 Exercise 2: Designing Multi-Zone HA Topology Constraints

In this exercise, you will design the scheduling rules for a mission-critical web frontend to ensure maximum availability and zone-outage resilience.

---

## 📋 Requirements & Constraints

You are deploying a web service named `order-processor`. You must configure its deployment to satisfy the following production SRE constraints:

1. **Replicas**: Exactly `4` running replicas.
2. **Zone Distribution**: The replicas must be evenly distributed across three availability zones (`us-central1-a`, `us-central1-b`, `us-central1-c`). The maximum skew between any two zones must not exceed `1`.
3. **Host Isolation**: Under normal conditions, no two replicas should run on the same worker node (host).
4. **Degraded State Grace**: If an entire availability zone (e.g. `us-central1-c`) fails, the pods in that zone must be rescheduled to the surviving zones (`us-central1-a` and `us-central1-b`). The scheduler is allowed to run more than 1 pod per node **only if** there are not enough nodes to satisfy the host isolation rule.

---

## 🎯 Challenge Goal

Draft the `spec.template.spec` portion of the Deployment manifest. Specifically, write the:
* `affinity` block (if needed)
* `topologySpreadConstraints` block

### Starter Template:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-processor
  namespace: production
spec:
  replicas: 4
  selector:
    matchLabels:
      app: order-processor
  template:
    metadata:
      labels:
        app: order-processor
    spec:
      containers:
        - name: web
          image: nginx:alpine
      # --- INSERT YOUR AFFINITY AND TOPOLOGY SPREAD CONSTRAINTS HERE ---
```

---

## 💡 Solution Guide & Walkthrough
*(Do not read this until you have attempted to solve it!)*

<details>
<summary>🔑 View Solution</summary>

To satisfy the requirements, we should configure a **hard** topology spread constraint for availability zones (to enforce `maxSkew: 1` strictly) and a **soft** host-level spread constraint (or affinity) for hosts so that host isolation is preferred but relaxed during a zone failure.

### Complete YAML Snippet:
```yaml
      topologySpreadConstraints:
        # Requirement 2: Strict zone distribution (maxSkew: 1)
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule  # Hard constraint
          labelSelector:
            matchLabels:
              app: order-processor

        # Requirement 3 & 4: Host isolation preferred, but relaxed under degradation
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway  # Soft constraint (allows scheduling if host-isolated nodes are full)
          labelSelector:
            matchLabels:
              app: order-processor
```

### Why this works:
1. `topology.kubernetes.io/zone` with `whenUnsatisfiable: DoNotSchedule` guarantees that the scheduler will never allow a skew greater than 1 across availability zones. If zone C goes down, the maximum skew constraint remains valid for the surviving zones (A and B), and they will split the 4 replicas evenly (2 in A, 2 in B).
2. `kubernetes.io/hostname` with `whenUnsatisfiable: ScheduleAnyway` ensures that Kubernetes *attempts* to put each pod on a separate host (skew 1). However, if Zone C fails, and Zone A and B only have 1 node each, the scheduler will degrade gracefully and schedule the 2nd pod on the same node rather than blocking scheduling (`Pending`).
</details>
