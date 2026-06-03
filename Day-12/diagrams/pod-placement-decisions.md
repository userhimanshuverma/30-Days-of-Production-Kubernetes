# 🎯 Pod Placement Decisions

This sequence diagram outlines the interaction loop between the Scheduler, Control Plane, and Kubelet that resolves the final placement of a Pod.

```mermaid
sequenceDiagram
    participant API as kube-apiserver
    participant Sched as kube-scheduler
    participant KubeletA as Kubelet (Node A)
    participant KubeletB as Kubelet (Node B)

    Note over API, Sched: Pod "web-app" applied (Requests: 2 CPU, 4Gi Mem)
    Sched->>API: Watch: Get unscheduled pods
    API-->>Sched: Pod "web-app" (Pending, nodeName: "")
    
    Sched->>Sched: Evaluate Node A & Node B capacity
    Note over Sched: Node A: 1 CPU free, 8Gi Mem free (Fails Filter)<br/>Node B: 3 CPU free, 6Gi Mem free (Passes Filter)
    
    Sched->>Sched: Node B selected (Score: 90)
    Sched->>Sched: Optimistic Reserve (Deduct 2 CPU, 4Gi Mem in local cache)
    
    Sched->>API: Bind Pod "web-app" to Node B
    API-->>Sched: 200 OK (Pod bound)

    KubeletB->>API: Watch: Get pods bound to Node B
    API-->>KubeletB: Pod "web-app" details
    
    Note over KubeletB: Kubelet admits Pod locally
    KubeletB->>KubeletB: Create container runtime sandbox
    KubeletB->>API: Patch Pod status (Running)
    
    %% Kubelet A does nothing
    Note over KubeletA: Watch: ignores Pod "web-app" (nodeName != Node A)
```

### Explanatory Summary
- The Scheduler is the decision-maker; it binds the Pod to a node in the API server.
- The Kubelet on the selected node is the worker that pulls the spec, reserves local resource capacity, builds the cgroup boundaries, and boots the container.
- Other Kubelets ignore the Pod since `spec.nodeName` does not match their own hostname.
