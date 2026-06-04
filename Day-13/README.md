# 🚀 Day 13: Autoscaling in Production
### 🏷️ PHASE 2 — RUNNING REAL APPLICATIONS

Welcome to Day 13. Today, we focus on the core capability that makes cloud-native systems resilient, cost-effective, and self-healing: **Autoscaling**. 

In production, workload demands change dynamically. A morning commute triggers API spikes; a marketing promotion drives flash sale traffic; a data pipeline processes millions of events in batches. Manually provisioned systems fail to handle these patterns without either massive cost overheads (over-provisioning) or service outages (under-provisioning).

Today, we will master the mechanics of Kubernetes autoscaling at the workload level (HPA and VPA) and the infrastructure level (Cluster Autoscaler), transforming your platform from a static collection of nodes into a dynamic, self-balancing engine.

---

## 🗺️ Day 13 Directory Structure

Here is how today's learning resources are organized:
- [notes/autoscaling-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-13/notes/autoscaling-deep-dive.md) — Mathematical mechanics of scaling, algorithm walkthroughs, and internal control loops.
- [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-13/diagrams/) — 12 detailed architecture and lifecycle diagrams.
- [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-13/manifests/) — Production-ready YAML configs for Metrics Server, HPAs, VPAs, and demo workloads.
- [labs/](file:///d:/30_Days_of_Production_Kubernetes/Day-13/labs/) — Hands-on labs (from Metrics Server setup to advanced custom Prometheus scaling).
  - [Lab 1: HPA, VPA, & Metrics Server](file:///d:/30_Days_of_Production_Kubernetes/Day-13/labs/lab-1-hpa-vpa-metrics.md)
  - [Lab 2: Advanced Autoscaling (Kafka, CA, Custom Policies)](file:///d:/30_Days_of_Production_Kubernetes/Day-13/labs/lab-2-advanced-autoscaling.md)
- [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-13/production-notes/lessons-learned.md) — Operational realities, cold starts, cost implications, and scaling delays.
- [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-13/troubleshooting/playbook.md) — Step-by-step resolution paths for stuck HPAs, pending nodes, and cost spikes.
- [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-13/exercises/challenges.md) — Real-world scenarios to practice configuring production limits and stabilization rules.
- [resources/autoscaling-command-center.html](file:///d:/30_Days_of_Production_Kubernetes/Day-13/resources/autoscaling-command-center.html) — Futuristic, interactive, single-page HTML simulator to visually experience multi-layer scaling.

---

## 1. Why Autoscaling Matters

In modern cloud infrastructure, capacity planning is no longer a static quarterly exercise. Operating statically provisioned clusters introduces a dangerous trade-off:

```
    Static Capacity: [==================================================] (100% Cost)
    Nightly Load:    [===] (5% Utilization - Massive cost waste)
    Daytime Peak:    [==================================] (60% Utilization)
    Spike Event:     [==========================================================] (115% Load - Outage!)
```

### Traffic Variability
Traffic patterns are rarely flat. SREs classify traffic patterns into:
* **Diurnal cycles:** Day-night waves driven by human behavior.
* **Sudden spikes:** Sudden rushes (e.g., breaking news, push notifications).
* **Step-changes:** Structural increases (e.g., marketing launches).
* **Batch processing:** Highly bursty, short-duration data operations.

### Cost vs. Performance
Maintaining a static resource pool large enough to handle the maximum annual traffic spike means paying for idle CPU and memory 99% of the year. Conversely, sizing clusters for average usage guarantees that the next traffic spike will trigger node exhaustion, OOM evictions, API slowdowns, and customer churn.

### Capacity Planning Challenges
Autoscaling shifts the paradigm from **reactive provisioning** to **declarative, intent-based scaling**. Instead of predicting how many virtual machines to rent, you define performance targets (e.g., "Maintain average CPU usage at 60%") and let Kubernetes provision workloads and nodes dynamically.

---

## 2. Horizontal Pod Autoscaler (HPA)

The HPA changes the *width* of your application by adjusting the number of Pod replicas in a `Deployment`, `StatefulSet`, or `ReplicaSet`.

```
            ┌──────────────┐
            │   API Load   │
            └──────┬───────┘
                   ▼
       ┌───────┬───────┬───────┐
       ▼       ▼       ▼       ▼
     [Pod]   [Pod]   [Pod]   [Pod]  <-- HPA adds or removes replicas
```

### The Metrics Server
By default, the Kubernetes Control Plane does not know how much CPU or memory a container is using. The **Metrics Server** is a cluster-wide aggregator that collects resource metrics from the Kubelet on each node via the `Summary API` (polling `/stats/summary` at a 15-second interval) and exposes them through the API Server as `/apis/metrics.k8s.io/`.

### CPU-Based Scaling
CPU utilization is calculated as a percentage of the Pod's **requested CPU**, *not* its limit.
$$\text{Pod CPU %} = \frac{\text{Current CPU Usage}}{\text{CPU Request}} \times 100$$
If a Pod has a CPU request of `500m` and runs at `400m` usage, its utilization is $80\%$. Setting an HPA target of $60\%$ will trigger a scale-up.

### Memory-Based Scaling
Memory scaling operates similarly, targeting a percentage of memory requests. However, memory scaling is often risky in production:
* **Garbage Collection Delay:** Runtime systems (like Java or Node.js) may not immediately release memory back to the OS, causing the HPA to scale up even when the active heap memory is low.
* **Scale-Down Risk:** Terminating memory-bound replicas can dump state/cache instantly, placing heavy load on remaining Pods.

### Custom and External Metrics
For asynchronous workloads or message brokers, resource usage (CPU/Memory) is a lagging indicator. You want to scale before CPU rises.
* **Custom Metrics:** API endpoints exposing application-internal metrics (e.g., HTTP request rate from Prometheus via Prometheus Adapter).
* **External Metrics:** Cloud-provider or external queue metrics (e.g., AWS SQS queue length or Kafka consumer lag).

### The HPA Scaling Algorithm
The HPA Controller executes a periodic check (default: `15 seconds`) using the following formula:

$$\text{desiredReplicas} = \lceil \text{currentReplicas} \times \frac{\text{currentMetricValue}}{\text{desiredMetricValue}} \rceil$$

#### Walkthrough Example:
* You have `3` current replicas.
* Current average CPU usage is `90m`.
* Desired (target) CPU usage is `50m`.
$$\text{desiredReplicas} = \lceil 3 \times \frac{90}{50} \rceil = \lceil 5.4 \rceil = 6 \text{ replicas}$$
The HPA will scale the Deployment up to 6 replicas.

---

## 3. Vertical Pod Autoscaler (VPA)

While HPA scales *out* (adding replicas), VPA scales *up* (adding CPU/Memory to existing replicas).

```
                      ┌───────────────┐
                      │  Limits       │
                      ├───────────────┤
                      │               │
      ┌───────────┐   │  Memory/CPU   │
      │ Memory/CPU│   │  (Optimized)  │  <-- VPA scales up resource settings
      └───────────┘   └───────────────┘
         Original          New Pod
```

### Recommender, Updater, and Admission Controller
VPA is split into three modular components:
1. **Recommender:** Analyzes historical resource usage (from Metrics Server or Prometheus) and computes target CPU and memory requests.
2. **Admission Controller:** An mutating admission webhook that intercepts Pod creation requests and injects the VPA's recommended resources.
3. **Updater:** Monitors running Pods. If their configured resources differ significantly from recommendations, the Updater evicts the Pod, forcing it to recreate and pull new configurations via the Admission Controller.

### Resource Optimization
VPA ensures pods are sized correctly, eliminating resource waste from developer "guesswork" (which typically results in over-estimating CPU/Memory requirements).

### When NOT to Use VPA
* **Do NOT use VPA and HPA together on CPU or Memory.** If both are active, they will fight: HPA will scale out replicas to lower CPU usage, while VPA will interpret the drop as a cue to shrink the Pod size, leading to resource thrashing.
* **Exception:** You can combine them if the HPA scales on custom business metrics (e.g., request rate) while the VPA manages physical limits (CPU/Memory).
* **Java/JVM Workloads:** VPAs can disrupt JVM workloads unless heap configuration is dynamically calculated relative to the container memory limit.

---

## 4. Cluster Autoscaler (CA)

Workload autoscalers (HPA/VPA) are bound by the physical limits of the cluster. If your nodes are full, new Pods will sit in a `Pending` state. The **Cluster Autoscaler (CA)** scales the *nodes* of your cluster.

```
      Pod: [Pending] --> (No Node has 2 CPU free)
                             │
                             ▼
      Cluster Autoscaler: API Call to AWS/GCP/Azure
                             │
                             ▼
      Resource Pool:     [ New Node Added ] --> Pod Schedules!
```

### Node Scaling Mechanics
Unlike HPAs, which check metrics, the Cluster Autoscaler monitors the **kube-scheduler**.
* **Scale-Up Trigger:** If a Pod is unschedulable (`FailedScheduling`) because no node has enough unreserved resources, the Cluster Autoscaler instantly detects the pending pod, calculates how many nodes are needed, and calls the cloud provider API to increase the capacity of the Node Group/Auto Scaling Group (ASG).
* **Scale-Down Trigger:** CA periodically checks if any node has utilization below a configured threshold (default: `50%` of requests). If a node's pods can be safely rescheduled elsewhere, the node is cordoned, drained, and terminated.

### Cloud Provider Integrations
CA uses drivers to interface with AWS Auto Scaling Groups, GCP Managed Instance Groups, or Azure Virtual Machine Scale Sets, ensuring node updates align with native cloud resource states.

---

## 5. Metrics Collection Pipeline

Autoscaling relies entirely on an observable metrics collection pipeline:

```
  ┌──────────────────────────────────────────────────────────┐
  │ 1. Application Container (Exposes metrics on /metrics)  │
  └────────────────────────────┬─────────────────────────────┘
                               │ (Prometheus Scrapes / Pulls)
                               ▼
  ┌──────────────────────────────────────────────────────────┐
  │ 2. Prometheus / metrics-server (Stores and aggregates)    │
  └────────────────────────────┬─────────────────────────────┘
                               │ (API Request / polling loop)
                               ▼
  ┌──────────────────────────────────────────────────────────┐
  │ 3. API Server Extension (apis/external.metrics.k8s.io)   │
  └────────────────────────────┬─────────────────────────────┘
                               │ (HPA Controller Loop)
                               ▼
  ┌──────────────────────────────────────────────────────────┐
  │ 4. HPA / VPA Controller (Calculates desired resources)   │
  └────────────────────────────┬─────────────────────────────┘
                               │ (Scale Deployment or Evict Pod)
                               ▼
  ┌──────────────────────────────────────────────────────────┐
  │ 5. Scaling Action Executed (Cluster adjusts capacity)    │
  └──────────────────────────────────────────────────────────┘
```

---

## 6. Real Production Examples

### E-commerce Flash Sales
* **Problem:** Traffic spikes from 2,000 to 100,000 requests per second in 30 seconds.
* **HPA Configuration:** Scale based on HTTP Request Rate (Prometheus custom metric). Set aggressive scale-up stabilization (`scaleUp: selectPolicy: Max`) and a high scale-up limit (allow scaling by $200\%$ per step).
* **Node Strategy:** Pre-provision warm standby nodes or configure low scaling thresholds to absorb the 3-minute cloud VM provisioning delay.

### Kafka Consumers
* **Problem:** A sudden batch ingestion lag occurs. CPU is low, but processing is falling behind.
* **HPA Configuration:** Scale on an external metric (`kafka_consumergroup_lag`). When the lag exceeds 10,000 offsets, scale-up replica counts up to the number of partitions (scaling past partition count leaves consumers idle).

### API Services
* **Problem:** Diurnal variations.
* **HPA Configuration:** Scale on CPU utilization ($60\%$). Use a standard 5-minute scale-down cooldown (`stabilizationWindowSeconds: 300`) to prevent node thrashing during brief traffic drops.

### Streaming Workloads
* **Problem:** Large video ingestion pipelines with high memory footprints.
* **HPA/VPA Strategy:** Set VPA to `RecommendationOnly` to analyze memory usage over weeks, helping configure accurate static limits. Use HPA to handle throughput-based scale-ups.

### Apache Pinot Clusters
* **Problem:** Real-time analytics nodes with extreme state.
* **Scaling Strategy:** HPA is avoided on query nodes (broker/servers) unless cache warm-up scripts are triggered upon new pod registration. Nodes must be scaled up slowly to prevent cold-cache query latency spikes.

### AI Inference Services
* **Problem:** GPU allocation and execution queues are highly variable.
* **Scaling Strategy:** Scale replicas based on GPU utilization (`nvidia.com/gpu`) and HTTP request queue length. Since GPU pods are slow to warm up (loading 20GB LLM weights), keep a min-replica buffer or use fast model registries.

---

## 🏁 Summary of Daily Tasks

To complete Day 13, proceed with the following steps:
1. **Explore Architecture Diagrams:** Walk through the [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-13/diagrams/) to visualize scale-up and scale-down lifecycles.
2. **Theoretical Deep-Dive:** Read the notes on [autoscaling-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-13/notes/autoscaling-deep-dive.md).
3. **Interactive Simulation:** Open the [Autoscaling Command Center Simulator](file:///d:/30_Days_of_Production_Kubernetes/Day-13/resources/autoscaling-command-center.html) in your browser to experiment with multi-layer scaling.
4. **Hands-on Labs:**
   * Run [Lab 1](file:///d:/30_Days_of_Production_Kubernetes/Day-13/labs/lab-1-hpa-vpa-metrics.md) to set up Metrics Server and test basic HPAs/VPAs.
   * Run [Lab 2](file:///d:/30_Days_of_Production_Kubernetes/Day-13/labs/lab-2-advanced-autoscaling.md) to practice custom metrics scaling and Cluster Autoscaler configurations.
5. **Read SRE Notes:** Study [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-13/production-notes/lessons-learned.md) to understand real-world scaling failures.
6. **Troubleshooting Practice:** Review the [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-13/troubleshooting/playbook.md).
7. **Complete Challenges:** Solve the optimization scenarios in [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-13/exercises/challenges.md).
