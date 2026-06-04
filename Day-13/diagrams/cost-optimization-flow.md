# 📐 Cost Optimization Flow

This flowchart shows the decision path for optimizing Kubernetes cluster run-costs via Autoscaling policies.

```mermaid
graph TD
    Start([Analyze Cluster Costs]) --> CheckLimits{Are pod requests<br/>close to actual usage?}
    
    CheckLimits -->|No| RunVPA[Run VPA in Recommendation Mode<br/>to resize Pod resources]
    CheckLimits -->|Yes| CheckNodes{Are worker nodes<br/>under-utilized < 50%?}
    
    CheckNodes -->|Yes| BinPack[Enable Bin Packing scoring<br/>to group workloads]
    CheckNodes -->|No| CheckSpot{Can workloads run on<br/>Spot/Preemptible instances?}

    BinPack --> DrainEmpty[Drain and Terminate empty nodes<br/>via Cluster Autoscaler / Karpenter]
    CheckSpot -->|Yes| SpotPools[Configure Spot Node Groups<br/>with HPA/Priority Fallbacks]
    CheckSpot -->|No| Reserved[Purchase Cloud Provider VM Reservation / Savings Plans]

    style Start fill:#EAECEE,stroke:#333
    style CheckLimits fill:#FCF3CF,stroke:#F1C40F
    style CheckNodes fill:#FCF3CF,stroke:#F1C40F
    style CheckSpot fill:#FCF3CF,stroke:#F1C40F
    style RunVPA fill:#D1F2EB,stroke:#1ABC9C,stroke-width:2px
    style BinPack fill:#D6EAF8,stroke:#2E86C1,stroke-width:2px
    style DrainEmpty fill:#D4EFDF,stroke:#27AE60,stroke-width:2px
    style SpotPools fill:#D4EFDF,stroke:#27AE60,stroke-width:2px
```

### Explanatory Summary
* **Resize Requests First:** The foundation of cluster cost optimization is configuring accurate pod requests. Over-provisioned requests reserve CPU/memory that goes unused, bloating cluster node size. Use VPA recommendations to shrink requests.
* **Consolidate Nodes:** Set scheduler priorities to "Bin Packing" (`NodeResourcesMostAllocated`) to pack pods together, freeing up under-utilized nodes so that the Cluster Autoscaler can terminate them.
* **Spot Instances:** For fault-tolerant microservices, deploy on Spot/Preemptible node pools, saving up to 70-80% compared to on-demand pricing.
