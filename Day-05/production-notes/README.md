# ⚡ Production-Grade Release Engineering Notes: Deployments at Scale

Operating deployments in large-scale production environments requires careful planning to prevent accidental outages, reduce blast radius, and ensure zero-downtime rollouts. These guidelines are compiled from lessons learned running mission-critical Kubernetes clusters.

---

## 1. Minimizing Deployment Blast Radius

A "blast radius" is the scope of damage that can occur if a release fails. In Kubernetes, you should isolate and constrain this radius using the following patterns:

### Pod Disruption Budgets (PDBs)
A PDB (`PodDisruptionBudget`) limits the number of Pods of a replicated application that can be down simultaneously due to voluntary disruptions (e.g., node drains, cluster upgrades, autoscaling scale-downs).
> [!IMPORTANT]
> If a cluster administrator drains a node hosting your pods, and you do not have a PDB, the node drain will terminate all your pods at once, causing a service outage.

Example PDB configuration for a payment API:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: payment-processor-pdb
  namespace: default
spec:
  minAvailable: 75%  # Or set maxUnavailable: 1
  selector:
    matchLabels:
      app: payment-processor
```
With this PDB, the Kubernetes API will block any voluntary drain operation that would drop the active replicas below 75%.

### Namespace and Resource Quotas
Never run production services in the same namespace as testing resources without resource limits. If a testing rollout leaks memory, it can starve the production pods on the same node. Set namespace-level `ResourceQuotas` and default `LimitRanges` to prevent resources from being overallocated.

---

## 2. Pod Anti-Affinity: Preventing Single Points of Failure

By default, the Kubernetes scheduler places Pods on nodes based on resource availability, not high-availability distribution. If you deploy 3 replicas of an API, the scheduler might place all 3 on the same physical node. If that node crashes, your entire service goes offline.

### Multi-AZ Distribution with Anti-Affinity
To guarantee high availability, use **Pod Anti-Affinity** to instruct the scheduler to distribute Pods across different nodes and Availability Zones (AZs).

```yaml
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - payment-processor
          topologyKey: topology.kubernetes.io/zone  # Force distribution across AZs
      - weight: 50
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - payment-processor
          topologyKey: kubernetes.io/hostname      # Prefer different physical nodes
```

---

## 3. Advanced Probe Tuning: Avoiding the "Death Spiral"

A common mistake in production is misconfiguring **Liveness Probes**, which can trigger a catastrophic cluster-wide "death spiral".

```
     ┌─────────────────────────────────────────────────────┐
     │                  Death Spiral Loop                  │
     ▼                                                     │
┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│ Client Load  │───>│ CPU Spike on │───>│ Liveness     │   │
│ Increases    │    │ Pods         │    │ Probe Fails  │   │
└──────────────┘    └──────────────┘    └──────────────┘   │
                                               │           │
                                               ▼           │
                                        ┌──────────────┐   │
                                        │ Container    │───┘
                                        │ Restarted    │
                                        └──────────────┘
```

1. **The CPU Spike**: A service experiences a sudden surge in traffic. CPU utilization hits 100%.
2. **Probe Latency**: Because the container is resource-starved, it fails to respond to the liveness probe HTTP check within the timeout period.
3. **The Restart**: Kubernetes assumes the application is dead and restarts the container.
4. **Cascading Failure**: The remaining pods must handle the extra traffic, causing them to fail their probes and restart. When the restarted pod comes back online, it immediately receives massive traffic and crashes again.

### Best Practices for Probes
* **Don't point Liveness Probes to deep dependencies**: The liveness probe should only check if the process is alive (e.g., a simple `/healthz` endpoint returning HTTP 200). Do not check database connectivity in a liveness probe; if the database goes down, restarting the container will not fix it and will only flood the cluster with restart operations.
* **Point Readiness Probes to shallow dependencies**: The readiness probe should verify if the pod can handle requests. If the database goes down, failing the readiness probe is acceptable because it stops routing traffic to this pod.
* **Use Startup Probes for legacy systems**: If your application takes 2 minutes to boot and load caches, set a `startupProbe` with a high `failureThreshold` (e.g., `failureThreshold: 24, periodSeconds: 5` = 2 minutes). This keeps liveness probes disabled until the boot completes, preventing boot-looping.
* **Increase Probe Timeout**: Set `timeoutSeconds: 2` or `3` instead of the default `1` to accommodate temporary garbage collection or CPU throttles.

---

## 4. The Database Migration Rollback Reality

In stateless applications, rolling back to an older version is easy. In systems with database schemas, rollbacks are highly dangerous if not planned.

If your v2.0.0 deployment applies a database migration that deletes a column, and you then trigger a `rollout undo` to v1.0.0, the v1.0.0 code will crash because it expects that deleted column.

### The Expand/Contract Pattern for Database Changes
To deploy database-backed applications safely:
1. **Expand**: Deploy database migrations that are backward-compatible. For example, add a new column, but do not delete the old one. Write data to both columns in the v2.0.0 code.
2. **Deploy Code**: Deploy the new application version. If it fails, you can roll back immediately because the database still contains the old column.
3. **Contract**: Once the release is verified as stable, apply a second migration to remove the old column and clean up legacy data.

---

## 5. Progressive Delivery with Argo Rollouts or Flagger

Native Kubernetes Deployments are L4 routing systems: they cannot split traffic precisely (e.g., exactly 1% of traffic) and cannot automatically roll back based on metrics.
For production setups, consider adopting:
* **Argo Rollouts**: A Custom Resource Definition (CRD) that replaces the standard Deployment. It integrates with L7 ingress controllers (Istio, Linkerd, Nginx Ingress) to route exact percentages of traffic and queries Prometheus metrics (error rate, latency) automatically to decide whether to advance the canary or abort and rollback.
* **Flagger**: A similar progressive delivery operator that automates canary rollouts using Istio, Linkerd, or App Mesh.
