# 📐 Multi-Layer Autoscaling Design

This diagram represents how Pod autoscaling (HPA/VPA) interacts with Node-level autoscaling (Cluster Autoscaler) inside a cluster.

```mermaid
graph TD
    subgraph WorkloadLevel ["Workload Scaling (Software Layer)"]
        direction TB
        HPA["HPA Controller<br/>(Scales Replica Count)"]
        VPA["VPA Controller<br/>(Scales Resource Sizes)"]
    end

    subgraph NodeLevel ["Infrastructure Scaling (Hardware Layer)"]
        direction TB
        CA["Cluster Autoscaler<br/>(Scales VM Count)"]
    end

    %% Interactions
    MetricsServer["Metrics Server / Prometheus"] -->|1. Feeds usage metrics| HPA
    MetricsServer -->|1. Feeds usage metrics| VPA
    
    HPA -->|2a. Requests more Pods| PodPool[Pod Replicas]
    VPA -->|2b. Adjusts Pod sizes| PodPool
    
    PodPool -->|3. Exhausts Node Resources| Scheduler[kube-scheduler]
    Scheduler -->|4. Pod sits Pending| Scheduler
    
    Scheduler -.->|5. Detects Pending state| CA
    CA -->|6. Provisions Nodes| WorkerNode[Physical / Virtual VM]
    WorkerNode -->|7. Satisfies scheduling| Scheduler

    style WorkloadLevel fill:#EAFAF1,stroke:#27AE60,stroke-width:2px
    style NodeLevel fill:#FDEDEC,stroke:#C0392B,stroke-width:2px
    style HPA fill:#58D68D,stroke:#1E8449,color:#fff
    style VPA fill:#5DADE2,stroke:#1F618D,color:#fff
    style CA fill:#EC7063,stroke:#922B21,color:#fff
    style Scheduler fill:#F4D03F,stroke:#9A7D0A,color:#fff
```

### Explanatory Summary
* **Two-Layer Autoscaling:** Kubernetes scaling must run in two coordinated layers: Workload-level scaling (adds replicas or changes memory/CPU targets) and Node-level scaling (supplies the physical hardware virtual machines).
* **Scheduling Link:** The two layers do not communicate directly. They coordinate asynchronously via the `kube-scheduler`. The workload layer requests more resources, which exhausts node space and triggers pending pods. The infrastructure layer (CA) reads the scheduler's failure states and provisions nodes accordingly.
