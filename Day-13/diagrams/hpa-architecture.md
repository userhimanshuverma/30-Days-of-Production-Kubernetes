# 📐 Horizontal Pod Autoscaler (HPA) Architecture

This diagram shows the architecture and data flow of the Horizontal Pod Autoscaler (HPA) control loop.

```mermaid
graph TD
    subgraph ControlPlane ["Kubernetes Control Plane"]
        HPAController["HPA Controller Loop<br/>(Runs every 15s)"]
        APIServer["API Server<br/>(/apis/metrics.k8s.io)"]
    end

    subgraph DataPlane ["Workload Nodes"]
        Kubelet1["Node 1 Kubelet<br/>(Summary API)"]
        Kubelet2["Node 2 Kubelet<br/>(Summary API)"]
        Pod1["Pod 1<br/>(Container CPU/Mem)"]
        Pod2["Pod 2<br/>(Container CPU/Mem)"]
    end

    MetricsServer["Metrics Server<br/>(Aggregator)"]
    Workload["Deployment / ReplicaSet<br/>(Scales replicas)"]

    %% Flow lines
    Pod1 -->|cgroups metrics| Kubelet1
    Pod2 -->|cgroups metrics| Kubelet2
    
    Kubelet1 -->|Scraped by| MetricsServer
    Kubelet2 -->|Scraped by| MetricsServer
    
    MetricsServer -->|Exposes metrics| APIServer
    HPAController -->|Queries metrics| APIServer
    HPAController -->|Computes Replicas| HPAController
    HPAController -->|Updates scale subresource| Workload
    Workload -->|Spawns / Terminates| Pod1
    Workload -->|Spawns / Terminates| Pod2

    style ControlPlane fill:#F3E9FA,stroke:#702D9C,stroke-width:2px
    style DataPlane fill:#EAF2F8,stroke:#1A5276,stroke-width:2px
    style HPAController fill:#A569BD,stroke:#5B2C6F,color:#fff
    style MetricsServer fill:#F5B041,stroke:#B9770E,color:#fff
    style APIServer fill:#5DADE2,stroke:#1F618D,color:#fff
    style Workload fill:#52BE80,stroke:#196F3D,color:#fff
```

### Explanatory Summary
1. **cgroups Resource Collection:** The containers on each node write resource usage statistics into Linux cgroups. The local **Kubelet** queries this data through the internal Summary API.
2. **Metrics Server Polling:** The **Metrics Server** periodically (usually every 15 seconds) polls the Kubelet endpoints `/stats/summary` to aggregate CPU and memory usage statistics.
3. **API Aggregation Layer:** The Metrics Server registers itself with the main **API Server** under the `/apis/metrics.k8s.io` path, making pod metrics queryable via standard API commands.
4. **HPA Controller Loop:** The **HPA Controller** runs a continuous loop (configured via `--horizontal-pod-autoscaler-sync-period`, default is 15 seconds) querying the API Server for target pod metrics, evaluating the scaling formula, and patching the target workload's `/scale` endpoint if a replica count change is required.
