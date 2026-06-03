# 🔄 Scheduling Workflow

This sequence diagram illustrates the step-by-step lifecycle of a Pod from the initial user request to the Kubelet starting the containers.

```mermaid
sequenceDiagram
    autonumber
    actor User as Platform Operator / DevOps
    participant API as kube-apiserver
    participant DB as etcd
    participant Sched as kube-scheduler
    participant Kubelet as Node Kubelet

    User->>API: kubectl apply -f pod.yaml
    API->>API: Validate & Mutate / Admit Pod
    API->>DB: Persist Pod state (Pending)
    DB-->>API: Persist Confirmed
    API-->>User: Pod Created (Pending)

    Note over Sched: List-Watch detects Pod with NodeName == ""
    Sched->>API: Fetch Pod Spec
    Sched->>Sched: Run Filtering Predicates
    Note right of Sched: Nodes filter to match requests
    Sched->>Sched: Run Scoring Priorities
    Note right of Sched: Nodes sorted by score
    Sched->>Sched: Select highest scoring Node
    Sched->>Sched: Reserve Node Resources in local cache
    
    Sched->>API: POST /api/v1/namespaces/default/bindings (Write Node binding)
    API->>DB: Update Pod Spec (nodeName: Node-A)
    DB-->>API: Confirmed
    API-->>Sched: Binding Success

    Note over Kubelet: List-Watch detects Pod with nodeName == Node-A
    Kubelet->>API: Fetch Pod Spec and ConfigMaps/Secrets
    Kubelet->>Kubelet: Create Cgroup Sandbox (cgroups v1/v2)
    Kubelet->>Kubelet: Run Container Runtime (CRI) to start Pod containers
    Kubelet->>API: Update Pod Status (Running)
    API->>DB: Persist Running status
```

### Explanatory Summary
1. **Admission Control:** The API Server authenticates and validates the Pod manifest.
2. **Detection:** The Scheduler's List-Watch loop discovers the pending Pod.
3. **Filtering & Scoring:** The Scheduler determines the best node based on current cluster resource bookings.
4. **Binding:** The Scheduler writes the chosen node back to the Pod's `spec.nodeName` field.
5. **Execution:** The Kubelet on the selected node watches for Pods with its node name, allocates the local Linux cgroups, pulls images, and runs the container.
