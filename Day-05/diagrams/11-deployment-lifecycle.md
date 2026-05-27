# 11 - Deployment Lifecycle and Status Conditions

This diagram charts the lifecycle states and transitions of a Kubernetes Deployment, focusing on the status conditions (`Progressing`, `Available`, `Failed`) reported in the resource status field.

```mermaid
stateDiagram-v2
    [*] --> Progressing : Spec updated / Rollout initiated
    
    state Progressing {
        [*] --> CreatingReplicaSet : Create new ReplicaSet
        CreatingReplicaSet --> ScalingReplicas : Scale up new / Scale down old
        ScalingReplicas --> PodsRunning : Pods created and starting
    }

    Progressing --> Available : Replicas >= spec.replicas - maxUnavailable <br> AND minReadySeconds satisfied
    Progressing --> Failed : progressDeadlineSeconds elapsed (default 10s min, 600s typical) <br> [Reason: ProgressDeadlineExceeded]

    Available --> Progressing : Spec changed (e.g., image update, replicas change)
    Failed --> Progressing : Spec updated with fix (e.g. correct image tag)

    state Available {
        [*] --> ServingTraffic
    }

    state Failed {
        [*] --> StalledRollout : Deployment stops progressing
    }
```
