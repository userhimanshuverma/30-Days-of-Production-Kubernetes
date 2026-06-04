# 🛡️ Platform Engineering Notes: Lessons Learned from Production Autoscaling

Operating autoscaling at scale in massive multi-tenant production clusters reveals operational challenges that static testing misses. This document outlines SRE lessons, failure post-mortems, and sizing recommendations.

---

## 1. The Scaling Delay: Anatomy of a Cold Start

When traffic spikes, the time it takes for a system to boot a new VM and serve traffic is a major latency vector.

```
Time: 0s               15s                  30s                    180s                 240s
[Spike Starts] ----> [HPA ScaleUp] ----> [CA VM Request] ----> [Node Joins] ----> [Container Ready]
                        (HPA Sync)         (Pending Pod)          (VM Boot)         (Image Pull/Probes)
```

### Delay Components
1. **HPA Sync Delay (15s):** Time before the metrics-server aggregates utilization and the HPA controller evaluates the threshold.
2. **CA Detection Delay (10s):** Time before the Cluster Autoscaler detects the unschedulable pod.
3. **Cloud VM Boot Delay (90s - 180s):** Cloud API execution, hardware allocation, OS boot, and Kubelet initialization.
4. **Container Image Pull Delay (30s - 120s):** Time spent pulling heavy container images over the network.
5. **App Initialization & Probes (10s - 60s):** Application boot-up, JVM heap compilation, dependency checks, and readiness probe success.

### Mitigation Strategies
* **Image Pre-pulling:** Use daemonsets to pre-pull large images to all nodes, or implement tools like **Spegel** or **Starlight** for peer-to-peer image caching.
* **Over-provisioning with Pause Pods:** Run lowest-priority deployments with high resource requests that act as placeholder "sacrificial space". When real pods scale up, they preempt the pause pods, acquiring node capacity instantly while the pause pods get pushed to pending, triggering VM scaling in the background.

---

## 2. HPA and CPU Throttling: The Silent Metric Killer

HPAs scaled on CPU usage can behave erratically under CPU throttling.
* **The Problem:** If a container has CPU limits configured and experiences severe throttling due to multi-threaded code, its average CPU utilization *looks high* to the metrics-server, triggering an HPA scale-up. However, the throughput remains low because CPU execution is bottlenecked by the CFS quota.
* **The Lesson:** For high-performance microservices, set CPU requests high (to guarantee scheduling capacity) but **omit CPU limits** or use **Static CPU Manager Policies** to avoid throttling loops. Scale the HPA on request rate or concurrency instead.

---

## 3. VPA Restart Trap: Eviction Cascades

VPAs running in `Auto` mode can trigger service outages if not configured with care.
* **The Scenario:** A microservice experiences a traffic spike. The VPA Recommender notices that the pod's CPU usage is exceeding requests and increases recommendations. The VPA Updater immediately **evicts** running pods to apply the new sizes.
* **The Outage:** If too many replicas are terminated simultaneously, the remaining pods are overwhelmed by traffic, their CPU spikes, VPA evicts them too, and the application plunges into a cascading crash loop.
* **Mitigation:**
  * Configure **PodDisruptionBudgets (PDBs)** to ensure a minimum percentage of replicas (e.g. `minAvailable: 70%`) remain active during VPA adjustments.
  * Keep VPA in `Off` (RecommendationOnly) mode for critical path user-facing workloads, utilizing manual platform pipelines to apply resizing.

---

## 4. Spot Instance Sizing & Priority Fallbacks

Spot instances cut cluster compute costs by up to $80\%$, but they can be reclaimed by the cloud provider with a 2-minute warning.
* **Spot Node Groups:** Configure Karpenter/CA to provision workloads onto Spot instances.
* **Priority Fallbacks:** Run critical pods on On-Demand nodes using Node Affinities. Use Spot nodes for workers or batch processors.
* **Graceful Termination:** Catch the cloud provider termination signal inside the cluster (e.g., using AWS Node Termination Handler) to drain pods instantly, rescheduling them before the node is reclaimed.

---

## 5. Real-World Autoscaling Post-Mortems

### Post-Mortem 1: The Metrics Aggregation Outage
* **Symptom:** A cluster with 300 microservices stopped scaling during a heavy traffic day, leading to multiple service timeouts.
* **Root Cause:** The `metrics-server` ran out of memory. Because the cluster size grew, the metrics polling payload increased, OOM-killing the metrics-server. The HPA controller could not query `/apis/metrics.k8s.io` and defaulted to keeping replicas static.
* **Resolution:** Configured VPA on the metrics-server itself, and increased its default resource limits. Set alerts for HPA sync failures.

### Post-Mortem 2: The E-commerce Scale-Down Storm
* **Symptom:** After a flash sale ended, traffic dropped, HPA scaled down pods, and the database experienced a massive connection spike, crashing the DB.
* **Root Cause:** On scale-down, hundreds of application pods terminated simultaneously. Each pod's preStop hooks were not configured, so they instantly dropped active database connections, causing connection pool exhaustions and lock cleanups on the DB server.
* **Resolution:** Implemented staggered scale-down stabilization windows (`stabilizationWindowSeconds: 600`) and added connection pooling (e.g. PgBouncer) to protect the DB from connection shocks.
