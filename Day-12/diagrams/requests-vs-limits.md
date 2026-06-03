# 📊 Requests vs Limits

This diagram visualizes how Kubernetes handles container allocations (requests) versus hard boundaries (limits) inside a host node.

```mermaid
graph TD
    subgraph Node ["Node Capacity: 4 CPU / 8Gi Memory"]
        subgraph Allocated ["Allocated System Registry (Scheduler View)"]
            ReqMem["Reserved Requests: 3Gi Memory (Guaranteed)"]
            AvailReq["Unreserved Request Capacity: 5Gi Memory (Available for Scheduling)"]
        end

        subgraph ContainerGroup ["Host Cgroup Tree (Kubelet Enforcement)"]
            subgraph Container ["Single Container Execution Context"]
                Usage["Actual Memory Usage (Dynamic)"]
                Req["Memory Request: 1Gi<br>(Guaranteed share in resource crunch)"]
                Lim["Memory Limit: 2Gi<br>(OOM Hard Limit - CFS throttle for CPU)"]
                
                Usage -- "Allowed to grow" --> Req
                Usage -- "Allowed to burst" --> Lim
                Usage -- "Exceeding limit triggers" --> OOM["OOM Killer (SIGKILL)"]
            end
        end
    end

    style Node fill:#F8F9FA,stroke:#333,stroke-width:2px
    style ReqMem fill:#28A745,stroke:#28A745,color:#fff
    style AvailReq fill:#17A2B8,stroke:#17A2B8,color:#fff
    style Req fill:#FFC107,stroke:#333,color:#333
    style Lim fill:#DC3545,stroke:#333,color:#fff
    style OOM fill:#721C24,stroke:#DC3545,color:#fff
```

### Explanatory Summary
- **Scheduler View:** Evaluates node allocatable capacity based purely on the sum of Pod resource **Requests**.
- **Kubelet View:** Enforces actual container usage using cgroups.
- **CPU Limits:** Monitored over 100ms windows; exceeding triggers **CFS Throttling**.
- **Memory Limits:** Exceeding triggers immediate **Out-of-Memory (OOM) termination**.
