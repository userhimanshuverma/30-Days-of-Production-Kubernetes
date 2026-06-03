# 🏢 Production Scheduling Architecture

This diagram illustrates how enterprise platforms structure node groups and use labels, taints, and tolerations to organize different types of application workloads.

```mermaid
graph TD
    subgraph "Workloads"
        API["API Pods<br/>(Burstable, Spread across zones)"]
        DB["Postgres Pod<br/>(Guaranteed QoS)"]
        Batch["Batch Worker<br/>(Spot instance preferred)"]
    end

    subgraph "Kubernetes Cluster Node Groups"
        subgraph NodeGroup1 ["Node Group: Database (On-Demand)"]
            Node1["Node-DB-1<br/>Taint: dedicated=database:NoSchedule<br/>Label: node-role.kubernetes.io/database=true"]
        end

        subgraph NodeGroup2 ["Node Group: General API (On-Demand)"]
            Node2["Node-API-1<br/>Label: topology.kubernetes.io/zone=us-east-1a"]
            Node3["Node-API-2<br/>Label: topology.kubernetes.io/zone=us-east-1b"]
        end

        subgraph NodeGroup3 ["Node Group: Batch (Spot Instances)"]
            Node4["Node-Batch-1<br/>Taint: dedicated=spot:NoSchedule<br/>Label: intent=batch"]
        end
    end

    %% Scheduling bindings
    DB -- "Tolerates: dedicated=database<br/>Affinity: node-role=database" --> Node1
    API -- "TopologySpreadConstraint:<br/>maxSkew=1, key=zone" --> Node2 & Node3
    Batch -- "Tolerates: dedicated=spot<br/>Affinity: intent=batch" --> Node4

    %% Karpenter connection
    Batch -. "If capacity is full" .-> Karpenter["Karpenter Autoscaler"]
    Karpenter -. "Provision new Spot Node" .-> NodeGroup3

    style NodeGroup1 fill:#E2E3E5,stroke:#333
    style NodeGroup2 fill:#D1ECF1,stroke:#333
    style NodeGroup3 fill:#FFF3CD,stroke:#333
    style Karpenter fill:#E1D5E7,stroke:#967ADC,stroke-width:2px
```

### Explanatory Summary
1. **Database Workloads:** Kept isolated on premium on-demand nodes using **Taints** (`dedicated=database:NoSchedule`) and **Node Affinity** to prevent noisy neighbors from scheduling there.
2. **Web APIs:** Scheduled across multiple availability zones using **Topology Spread Constraints** to ensure high availability.
3. **Batch Processing:** Uses cheaper Spot instances by tolerating spot taints, allowing significant cost reductions without risking core systems.
4. **Karpenter:** Dynamically intercepts scheduling failures for unschedulable pods, automatically provisioning matching nodes with custom labels/taints directly in AWS/GCP.
