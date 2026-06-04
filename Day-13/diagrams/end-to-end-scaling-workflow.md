# 📐 End-to-End Scaling Workflow

This sequence diagram details the full, chronologically ordered path of events during a massive traffic spike.

```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant Ingress as Ingress Controller
    participant Pod as Running Pod
    participant MS as Metrics Server
    participant HPA as HPA Controller
    participant Scheduler as Kube-Scheduler
    participant CA as Cluster Autoscaler
    participant Cloud as Cloud Provider API

    Client->>Ingress: Massive traffic surge
    Ingress->>Pod: Routes heavy HTTP load
    Note over Pod: Pod CPU usage spikes past target (e.g. >80%)
    MS->>Pod: Polls CPU/Memory utilization
    HPA->>MS: Requests workload metric average
    Note over HPA: Calculates scaling formula
    HPA->>Scheduler: Updates Replica count (e.g. scales 3 -> 10)
    Note over Scheduler: Attempts to schedule 7 new pods
    Scheduler-->>Scheduler: Finds no node has resources left
    Scheduler->>Scheduler: Marks remaining pods as Pending (FailedScheduling)
    CA->>Scheduler: Detects Pending pods
    Note over CA: Runs simulation and finds node template fits
    CA->>Cloud: Scale-up API request (Add 2 VMs to Node Group)
    Note over Cloud: Boots and bootstraps 2 new VMs
    Cloud->>Scheduler: New Nodes register with cluster
    Scheduler->>Pod: Schedules remaining Pending pods
    Ingress->>Pod: Routes client traffic to new pods
```

### Explanatory Summary
1. **Workload Ingestion:** High traffic flows through the **Ingress Controller** to the existing pods, triggering elevated CPU utilization.
2. **Workload Scale-up:** The **Metrics Server** grabs these utilization spikes. The **HPA Controller** calculates that the workload requires more replicas and updates the deployment, causing the ReplicaSet controller to generate new pod requests.
3. **Pending Trigger:** The **Scheduler** places as many pods as the existing cluster capacity allows. The remaining pods are marked as `Pending` with a `FailedScheduling` reason.
4. **Infrastructure Scale-up:** The **Cluster Autoscaler** detects these pending pods, calls the **Cloud API** to add VMs, and waits. Once the VMs join the cluster, the Scheduler successfully places the remaining pods, establishing a higher cluster capacity.
