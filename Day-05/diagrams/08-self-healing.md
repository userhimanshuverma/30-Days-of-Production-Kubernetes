# 08 - Self-Healing Workflow

This diagram shows how Kubernetes performs self-healing. When a Pod fails or a Node becomes unresponsive, the ReplicaSet controller detects the deficit via its reconciliation loop and schedules a new Pod on a healthy node automatically.

```mermaid
graph TD
    %% Styling
    classDef state fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef node_ok fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;
    classDef node_fail fill:#1e1e2e,stroke:#f38ba8,stroke-width:2px,color:#cdd6f4;
    classDef ctrl fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;

    subgraph State Monitoring
        RS[ReplicaSet Controller: Replicas = 3]:::ctrl
    end

    subgraph Cluster Nodes
        subgraph Node1 [Worker Node 1 - Healthy]
            Pod1[Pod A - Running]:::node_ok
            Pod2[Pod B - Running]:::node_ok
        end

        subgraph Node2 [Worker Node 2 - CRASHED]:::node_fail
            Pod3[Pod C - Unreachable]:::node_fail
        end
        
        subgraph Node3 [Worker Node 3 - Healthy]
            PodNew[Pod D - Scheduled]:::node_ok
        end
    end

    RS -->|1. Monitors Status| Pod1
    RS -->|1. Monitors Status| Pod2
    RS -->|1. Monitors Status| Pod3

    Node2 -->|2. Node heartbeats stop| LeaseExpired[Node lease expires / node unreachable]:::node_fail
    RS -->|3. Reconciliation diff: Desired=3, Actual=2| Recover[Trigger Pod Recreation]:::state
    Recover -->|4. Create Pod D| PodNew
    
    style Node2 fill:#2a1c24,stroke:#f38ba8
    style Node1 fill:#1e1e2e,stroke:#a6e3a1
    style Node3 fill:#1e1e2e,stroke:#a6e3a1
```
