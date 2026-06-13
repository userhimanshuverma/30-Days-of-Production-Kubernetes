# ⚙️ Scheduling Profiles & Configurations

Kubernetes supports running multiple schedulers or a single scheduler with multiple **Scheduling Profiles**. A scheduling profile allows you to configure different filtering, scoring, and binding behaviors for different classes of workloads.

---

## 🏗️ KubeSchedulerConfiguration Architecture

The scheduler's behavior is configured using the `KubeSchedulerConfiguration` API resource. Rather than deploying multiple scheduler binaries (which adds operational overhead and leads to cache inconsistency), you can define multiple profiles within a single config file.

```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
  - schedulerName: low-latency-scheduler
    plugins:
      ...
  - schedulerName: bin-packing-scheduler
    plugins:
      ...
```

Pods can select which profile (and therefore which rules) to use by specifying the `schedulerName` in their PodSpec:

```yaml
spec:
  schedulerName: bin-packing-scheduler
  containers:
    - name: app
      image: nginx
```

---

## 🔌 Scheduling Extension Points

A Scheduling Profile customizes the scheduler by enabling, disabling, or re-weighting plugins at different **extension points**:

| Extension Point | Phase | Description |
|---|---|---|
| `QueueSort` | Queueing | Sorts pods in the scheduling queue. (Only one QueueSort plugin can be enabled per scheduler). |
| `PreFilter` | Filtering | Pre-processes pod information or checks cluster state before filtering. |
| `Filter` | Filtering | Determines if a node can run the pod. (Equivalent to Predicates). |
| `PostFilter` | Filtering | Invoked only when no feasible nodes are found. Used for **Preemption** triggers. |
| `PreScore` | Scoring | Pre-processes state to generate inputs for scoring plugins. |
| `Score` | Scoring | Rates nodes on a scale from 0 to 100 based on priorities. (Equivalent to Priorities). |
| `NormalizeScore` | Scoring | Normalizes scoring outcomes from different plugins before applying weights. |
| `Reserve` | Reserving | Reserves resources on the chosen node in the scheduler's local cache before writing to the API. |
| `Permit` | Reserving | Can approve, deny, or delay binding (used to wait for co-scheduling pods). |
| `PreBind` | Binding | Runs tasks (like mounting volumes) before the binding is written. |
| `Bind` | Binding | Binds the Pod to the Node by posting a Binding object to the API Server. |
| `PostBind` | Binding | Informational phase called after the Pod is successfully bound. |

---

## ⚖️ Custom Plugin Re-weighting

In the scoring phase, multiple plugins run and assign a score of 0-100 to each node. The scheduler computes a weighted sum:

$$\text{Final Score} = \sum (\text{Plugin Score} \times \text{Weight})$$

By tweaking plugin weights in [scheduler-config.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-22/scheduler/scheduler-config.yaml), you can balance cluster resources:

* **LeastAllocated (default)**: Spreads workloads across all nodes (configured via `scoringStrategy.type: LeastAllocated` in the `NodeResourcesFit` plugin settings).
* **MostAllocated (bin packing)**: Groups workloads tightly to maximize density, enabling cluster autoscalers to terminate idle nodes and save costs.

```yaml
    pluginConfig:
      - name: NodeResourcesFit
        args:
          scoringStrategy:
            type: MostAllocated
            resources:
              - name: cpu
                weight: 1
              - name: memory
                weight: 1
```
