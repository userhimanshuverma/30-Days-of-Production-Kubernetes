# 📐 Pod Scaling Lifecycle

This state machine diagram visualizes the phases a Pod undergoes during scaling transitions.

```mermaid
stateDiagram-v2
    [*] --> HPADecision : Traffic Spike Detected
    HPADecision --> PodCreation : Replica Count Incremented
    PodCreation --> Pending : Scheduler evaluation
    state Pending {
        [*] --> FilterNodes
        FilterNodes --> ScoreNodes
        ScoreNodes --> BindNode
    }
    Pending --> Scheduled : Node Assigned
    Scheduled --> PullingImage : Container Runtime init
    PullingImage --> ContainerStarting : Entrypoint invoked
    ContainerStarting --> Running : StartupProbe Passes
    Running --> Ready : ReadinessProbe Passes (Traffic Routed)
    
    %% Scale down path
    Ready --> Terminating : Scale Down Triggered (Stabilization Window)
    state Terminating {
        [*] --> DeRegisterIngress : Traffic Stop Routing
        DeRegisterIngress --> PreStopHook : Executing preStop scripts
        PreStopHook --> SIGTERM : Kernel sends termination signal
        SIGTERM --> SIGKILL : Grace Period Exceeded (Default 30s)
    }
    Terminating --> [*] : Pod Resources Reclaimed
```

### Explanatory Summary
1. **Provisioning Cycle:** Once the HPA decides to scale out, a pod is created. It starts in the `Pending` state while the scheduler filters, scores, and binds it to a node.
2. **Warm-up Cycle:** The node runtime pulls the container images and starts the container. The pod becomes `Running` when its `StartupProbe` passes, and `Ready` (traffic starts routing) when its `ReadinessProbe` passes.
3. **Termination Cycle:** During scale-down, the replica count is reduced. The pod transitions to `Terminating`. Ingress stops routing new connections, the `preStop` hook executes (allowing active connections to drain), a `SIGTERM` signal is dispatched, and if the container fails to exit within the grace period, a `SIGKILL` is sent.
