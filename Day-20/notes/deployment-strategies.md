# 📔 Kubernetes Deployment Strategies: Rolling, Blue/Green, and Canary

In cloud-native production environments, service availability is a primary SRE metric. How we transition our application from version V1 to version V2 dictates whether our customers experience zero-downtime upgrades or frustrating micro-outages.

This note covers the three primary deployment strategies, their mechanics, and the trade-offs of each.

---

## 🌀 1. Rolling Update (The Kubernetes Default)

The Rolling Update strategy replaces instances of the old version with instances of the new version gradually, pod by pod.

```
Initial State:  [V1] [V1] [V1] [V1]
Step 1:         [V2] [V1] [V1] [V1] (Spins up V2, terminates one V1)
Step 2:         [V2] [V2] [V1] [V1]
Step 3:         [V2] [V2] [V2] [V1]
Final State:    [V2] [V2] [V2] [V2]
```

### Manifest Configuration:
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%       # How many pods can be created above target replica count
      maxUnavailable: 0%  # How many pods can be unavailable during update
```

### The Math: `maxSurge` & `maxUnavailable`
If you have `replicas: 4`:
* `maxSurge: 25%` (equivalent to 1 pod): Kubernetes can spin up 1 temporary new pod, bringing the total pods to 5 during transition.
* `maxUnavailable: 0%`: Kubernetes cannot terminate *any* old pods until the new pods are fully healthy (probes passing).
* **Result:** At least 4 pods are guaranteed healthy at all times.

### Trade-offs:
* **Pros:** Built natively into Kubernetes; no extra tools required; memory/CPU overhead is capped by the surge value.
* **Cons:** Both V1 and V2 pods receive traffic at the same time. If V2 introduces a API change that is not backward-compatible, users hitting V1 pods might fail. Rollbacks require running another rolling update in reverse, which can take several minutes.

---

## 🟢🔵 2. Blue/Green Deployments

Blue/Green deployments maintain two physical versions of the application running simultaneously, with a router (Kubernetes Service) pointing to only one.

```
                    +------------------------+
                    |  Client Request Traffic|
                    +-----------+------------+
                                |
                                ▼
                    +------------------------+
                    |   Kubernetes Service   |
                    | selector: version=v1   |
                    +-----------+------------+
                                |
             +------------------+------------------+
             | (100% Traffic)                      | (0% Traffic)
             ▼                                     ▼
+------------------------+            +------------------------+
|    Blue Deployment     |            |    Green Deployment    |
|      Version V1        |            |      Version V2        |
+------------------------+            +------------------------+
```

### How it Works:
1. **Blue** (V1) is currently live, and the Service selectors point to `version: v1`.
2. SRE deploys **Green** (V2) in the cluster, completely separate.
3. Automated validation runs against Green (using internal service URLs/headers).
4. If Green is healthy, the SRE or GitOps pipeline updates the Service manifest to point selectors to `version: v2`.
5. Traffic shifts instantly to Green.
6. Blue is left running for a cooling period. If an error is spotted, the Service selector is instantly switched back to `version: v1`.

### Trade-offs:
* **Pros:** Instant cutover and instant rollback (no delay waiting for pods to scale). No API version mix.
* **Cons:** Requires double the infrastructure resources during deployment. If your app is large, you might hit resource quotas.

---

## 🐤 3. Canary Deployments

Canary deployments expose the new version to a small, controlled group of users (e.g., 5%) before rolling out to the entire cluster.

```
                    +------------------------+
                    |  Client Request Traffic|
                    +-----------+------------+
                                |
                                ▼
                    +------------------------+
                    |   Ingress / Mesh Router|
                    +-----+------------+-----+
                          | (90%)      | (10%)
                          ▼            ▼
                     +--------+    +--------+
                     | V1 Pod |    | V2 Pod |
                     +--------+    +--------+
```

### How it Works:
1. Deploy a small number of V2 pods.
2. Configure your Ingress Controller (NGINX, Envoy, Traefik) or Service Mesh (Istio, Linkerd) to route a small fraction of traffic to the V2 pods.
3. Gather metrics via Prometheus (HTTP error rates, response latencies, system errors).
4. Gradually increase the traffic share (e.g., 10% -> 25% -> 50% -> 100%) if metrics remain within SLA boundaries.
5. If metrics fail (e.g., HTTP 5xx spikes), immediately drop V2 traffic weight to 0%.

### Trade-offs:
* **Pros:** Safest strategy; exposes bugs to real-world traffic with minimal customer blast radius; validates performance in production.
* **Cons:** Requires complex architecture (Service Mesh, Ingress plugins, automated metric judgment engines like Flagger or Argo Rollouts).

---

## 📊 Comparison Matrix

| Metric | Rolling Update | Blue/Green | Canary |
| :--- | :--- | :--- | :--- |
| **Infra Resource Overhead** | Minimal (controlled by `maxSurge`) | High (Double / 100% surge) | Low (only canary pods initialized) |
| **Rollback Speed** | Slow (requires reverse deployment) | Instant (Service selector swap) | Instant (Traffic weight set to 0%) |
| **Implementation Effort** | None (Built-in) | Medium (Service routing logic) | High (Requires Service Mesh / Flagger) |
| **Blast Radius of Bad Release**| High (all users can hit V2) | Medium (detected during validation) | Low (isolated to traffic percentage) |
| **Best Used For** | Stateless apps, non-critical services | Stateful systems, DB schema dependencies | High-traffic critical user-facing microservices |
