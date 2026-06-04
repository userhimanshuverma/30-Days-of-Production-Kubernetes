# 📐 Cluster Autoscaler (CA) Architecture

This diagram shows how the Cluster Autoscaler monitors unschedulable pods and triggers infrastructure expansion.

```mermaid
graph TD
    subgraph K8sCluster ["Kubernetes Cluster"]
        PendingPod["Pending Pod<br/>(FailedScheduling)"]
        Scheduler["Kube-Scheduler<br/>(Fails to place Pod)"]
        CA["Cluster Autoscaler<br/>(Loop: 10s)"]
        Nodes["Active Nodes"]
    end

    subgraph CloudProvider ["Cloud Provider (AWS/GCP/Azure)"]
        ASG["Node Group / ASG<br/>(VM Pool)"]
        VM["New Virtual Machine"]
    end

    %% Flow lines
    PendingPod -->|1. Cannot schedule| Scheduler
    Scheduler -->|2. Sets status: Unschedulable| PendingPod
    CA -->|3. Watches status| PendingPod
    CA -->|4. Runs simulation: Can a new node fix it?| CA
    CA -->|5. Triggers scale-up API| ASG
    ASG -->|6. Provisions| VM
    VM -->|7. Joins cluster as Node| Nodes
    Scheduler -->|8. Schedules Pod| Nodes

    style K8sCluster fill:#EAF2F8,stroke:#1A5276,stroke-width:2px
    style CloudProvider fill:#FEF9E7,stroke:#D35400,stroke-width:2px
    style CA fill:#AF7AC5,stroke:#6C3483,color:#fff
    style Scheduler fill:#5DADE2,stroke:#1B4F72,color:#fff
    style ASG fill:#E67E22,stroke:#A04000,color:#fff
    style VM fill:#52BE80,stroke:#145A32,color:#fff
```

### Explanatory Summary
1. **Unschedulable Detection:** When a pod requests more CPU/memory requests than any single active node can offer, the **Kube-Scheduler** marks the pod status as `Pending` with a `FailedScheduling` event.
2. **Simulation Check:** The **Cluster Autoscaler** loop watches for these unschedulable pods. It executes a local simulation using node-group templates to check if adding a node to one of the groups will satisfy the pod's constraints (e.g., node selectors, taints, tolerations).
3. **Cloud Provisioning:** If a match is found, CA directly calls the cloud provider's API (e.g., AWS EC2 Auto Scaling, GCP Compute Engine Managed Instance Groups) to increment the group size.
4. **Integration:** Once the new VM boots up and runs the kubelet script, it registers itself with the Kubernetes API Server. The `kube-scheduler` immediately schedules the pending pod to this new node.
