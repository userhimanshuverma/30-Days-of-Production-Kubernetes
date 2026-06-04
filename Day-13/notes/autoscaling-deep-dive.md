# 🧠 Deep-Dive: Kubernetes Autoscaling Mechanics

To operate autoscaling in high-throughput production clusters, you must understand the mathematical models, API endpoints, and control loops running inside the Kubernetes Control Plane.

---

## 1. HPA Mathematical Model & Algorithm Details

The Horizontal Pod Autoscaler controller does not execute arbitrary replica changes. It operates on a strict, synchronous control loop (default sync period: `15 seconds`) running the following mathematical formula:

$$\text{desiredReplicas} = \left\lceil \text{currentReplicas} \times \left( \frac{\text{currentMetricValue}}{\text{desiredMetricValue}} \right) \right\rceil$$

### Algorithm Execution Steps

1. **Query Phase:** The HPA controller queries the API Server (`/apis/metrics.k8s.io`, `/apis/custom.metrics.k8s.io`, or `/apis/external.metrics.k8s.io`) for the metrics defined in the HPA spec.
2. **Filtering Phase (Metric Exceptions):**
   * **Pods without readiness:** If a pod is in the process of starting up and does not have the `Ready` condition, its metrics are excluded.
   * **Pods missing metrics:** If a pod has crashed or failed to report metrics, it is set aside during the averaging calculation.
   * **Cool-off window adjustments:** If the HPA scaled up recently, it ignores downscale recommendations that fall within the stabilization window.
3. **Calculation Phase:**
   * It takes the sum of the target metric across all valid pods and divides it by the total number of pods to get the `currentMetricValue`.
   * It divides the `currentMetricValue` by the `desiredMetricValue` (target threshold).
   * It multiplies this ratio by the `currentReplicas` and takes the **ceiling** ($\lceil \dots \rceil$) of the result.
4. **Tolerance Filter:**
   * To prevent tiny oscillations, the HPA has a hardcoded global tolerance factor (default: `0.1` or $10\%$).
   * If the ratio of `currentMetricValue / desiredMetricValue` is between `0.9` and `1.1` (within $10\%$ of the target), no scaling action is taken.
5. **Execution Phase:**
   * If the calculated replica count differs from current replicas (and falls outside the tolerance), the controller calls the Scale subresource of the target workload (e.g. `/apis/apps/v1/namespaces/default/deployments/my-service/scale`) to patch the replica field.

---

## 2. VPA Recommender & Admission Control

The VPA operates with three decoupled micro-services, preventing single points of failure from stopping application workloads.

```
                          +-------------------------+
                          |   Metrics Collection    |
                          +------------┬------------+
                                       │ (Metrics Server / Prometheus)
                                       ▼
  +-------------------------------------------------------------------------+
  |                             VPA Recommender                             |
  |                                                                         |
  |  1. Calculates decaying exponential moving average of CPU usage.       |
  |  2. Calculates 95th percentile of memory usage peaks.                    |
  |  3. Writes recommendations to VPA CRD status.                           |
  +------------------------------------┬------------------------------------+
                                       │
                                       ▼
  +------------------------------------+------------------------------------+
  |                               VPA Updater                               |
  |                                                                         |
  |  1. Evaluates target vs actual resource requests.                       |
  |  2. If deviation > threshold, evicts the Pod.                           |
  +------------------------------------┬------------------------------------+
                                       │ (Triggers Pod recreation)
                                       ▼
  +------------------------------------+------------------------------------+
  |                      VPA Mutating Webhook Admission                     |
  |                                                                         |
  |  1. Intercepts pod creation request.                                    |
  |  2. Overwrites spec.containers[*].resources with target values.        |
  +-------------------------------------------------------------------------+
```

### Recommendation Math
The **Recommender** calculates resource recommendations based on historical usage metrics:
* **CPU:** Calculated using a decay rate. It acts as an **exponential moving average** (EMA) to ensure that recent CPU spikes weight heavier than historical idle states.
* **Memory:** Memory is analyzed using a **peak rolling window** (default: 8 days). The Recommender takes the $95\text{th}$ percentile of the peak memory usage over this window to compute the recommendation, adding a safety margin (default: $15\%$) to prevent OOM events.

---

## 3. Cluster Autoscaler Simulation Logic

The Cluster Autoscaler (CA) does not look at CPU/Memory utilization to scale up. It listens to scheduling events.

### The Scale-Up Control Loop
1. **Identify Unschedulable Pods:** The CA queries the API Server for pods with `status.phase = Pending` and `FailedScheduling` events in the scheduler logs.
2. **Filter Out ineligible Pods:**
   * Pods with local storage requirements (unless overridden).
   * Pods restricted by strict anti-affinity rules.
3. **Simulate Virtual Provisioning:**
   * CA reads the cluster's configured Node Groups (ASGs / MIGs).
   * For each Node Group, it reads the node template (labels, taints, capacity).
   * It runs a **mock scheduler simulation**: *"If I add a node of type X, will the pending pods fit?"*
4. **Choose Best Node Group:** If multiple node groups fit, CA selects based on the configured expander policy:
   * `random`: Selects randomly.
   * `most-pods`: Selects the node group that schedules the maximum number of pending pods.
   * `least-waste`: Selects the group that leaves the least idle CPU/Memory after scheduling.
   * `price`: Selects the cheapest instance type.
5. **Request Scale-Up:** Calls the cloud provider API to increase the desired capacity by $N$ instances.

### The Scale-Down Control Loop
1. **Scan for Under-Utilized Nodes:** CA runs every 10 seconds and checks if any node's resource requests sum to **less than 50%** of its capacity.
2. **Evaluate Drain Safety:** A node is ineligible for scale-down if:
   * It hosts pods that cannot be evicted (e.g. system-critical pods without priority classes).
   * Evicting its pods would violate a **PodDisruptionBudget (PDB)**.
   * The pods cannot fit onto other remaining nodes.
3. **Cordon, Drain, and Terminate:** If a node is eligible, CA marks it as unschedulable (Cordon), evicts its pods (Drain), and terminates the underlying VM after a stabilization delay.
