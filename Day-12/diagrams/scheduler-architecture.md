# 🏗️ Scheduler Architecture

This diagram illustrates the internal components of the `kube-scheduler` and how it interacts with the control plane cache and queue.

```mermaid
graph TD
    subgraph "Kubernetes Control Plane"
        APIServer["kube-apiserver"]
        ETCD[(etcd)]
        APIServer <--> ETCD
    end

    subgraph "kube-scheduler Internals"
        Informer["SharedInformer (List-Watch Nodes/Pods)"]
        Cache["Scheduler Cache (Node State & Bookkeeping)"]
        
        subgraph "Scheduling Queue"
            ActiveQ["Active Queue (Priority Queue)"]
            BackoffQ["Backoff Queue"]
            UnschedQ["Unschedulable Pods Pool"]
        end

        subgraph "Scheduling Pipeline"
            Filtering["Filtering (Predicates)"]
            Scoring["Scoring (Priorities)"]
            Reserve["Reserve (Optimistic Binding)"]
            Permit["Permit (Pre-Binding checks)"]
            PreBind["Pre-Bind"]
            Bind["Bind (Write binding to API Server)"]
        end
    end

    %% Informer / Cache loops
    APIServer -- "Watch Events" --> Informer
    Informer -- "Update Cache" --> Cache
    Informer -- "Enqueue Pods" --> ActiveQ

    %% Pipeline flow
    ActiveQ -- "Next Pod" --> Filtering
    Filtering --> Scoring
    Scoring --> Reserve
    Reserve --> Permit
    Permit --> PreBind
    PreBind --> Bind
    Bind -- "Post Bind Request" --> APIServer

    %% Cache feedback
    Reserve -- "Optimistically Update Cache" --> Cache
    Bind -- "Confirm Placement" --> Cache
    Permit -- "Fail/Reject" --> BackoffQ
    Filtering -- "Failed Nodes" --> UnschedQ
    BackoffQ -- "Retrying" --> ActiveQ
    UnschedQ -- "Cluster State Change" --> ActiveQ

    style APIServer fill:#743FDB,stroke:#333,stroke-width:2px,color:#fff
    style Cache fill:#17A2B8,stroke:#333,stroke-width:2px,color:#fff
    style ActiveQ fill:#28A745,stroke:#333,stroke-width:1px,color:#fff
    style Filtering fill:#FD7E14,stroke:#333,stroke-width:1px,color:#fff
    style Scoring fill:#FD7E14,stroke:#333,stroke-width:1px,color:#fff
    style Bind fill:#DC3545,stroke:#333,stroke-width:1px,color:#fff
```

### Explanatory Summary
1. **SharedInformer:** Watches the API Server for new Pods (with `spec.nodeName` blank) and nodes.
2. **Scheduling Queue:** Pods are kept in an active priority queue. If they fail to schedule, they enter the backoff queue or the unschedulable pool until cluster resources change.
3. **Pipeline Stages:**
   - **Filtering:** Filters out non-viable nodes.
   - **Scoring:** Ranks remaining nodes.
   - **Reserve:** Temporarily claims resources in memory (Scheduler Cache) to prevent race conditions (optimistic scheduling).
   - **Bind:** Submits the binding manifest back to the API Server.
