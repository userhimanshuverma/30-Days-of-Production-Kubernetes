# 📦 Bin Packing vs Spread

This diagram contrasts the default "Spread" (Least Allocated) strategy with the "Bin Packing" (Most Allocated) strategy.

```mermaid
graph TD
    subgraph SpreadStrategy ["Spread (Least Allocated) - Balanced Load"]
        direction LR
        SNode1["Node 1<br/>[Pod A]<br/>CPU: 30% Utilization"]
        SNode2["Node 2<br/>[Pod B]<br/>CPU: 30% Utilization"]
        SNode3["Node 3<br/>[Pod C]<br/>CPU: 30% Utilization"]
    end

    subgraph BinPackStrategy ["Bin Packing (Most Allocated) - Cost Optimized"]
        direction LR
        BNode1["Node 1<br/>[Pod A, Pod B, Pod C]<br/>CPU: 90% Utilization"]
        BNode2["Node 2<br/>[Empty]<br/>CPU: 0% (Can terminate)"]
        BNode3["Node 3<br/>[Empty]<br/>CPU: 0% (Can terminate)"]
    end

    style SpreadStrategy fill:#E2E3E5,stroke:#333
    style BinPackStrategy fill:#D1ECF1,stroke:#333
    style SNode1 fill:#FFC107,stroke:#333
    style SNode2 fill:#FFC107,stroke:#333
    style SNode3 fill:#FFC107,stroke:#333
    style BNode1 fill:#28A745,stroke:#333,color:#fff
    style BNode2 fill:#DC3545,stroke:#333,color:#fff
    style BNode3 fill:#DC3545,stroke:#333,color:#fff
```

### Explanatory Summary
- **Spread:** Pods are distributed evenly across nodes. Good for safety and performance isolation, but results in high under-utilization and prevents cluster downscaling (higher cost).
- **Bin Packing:** Pods are tightly packed onto the minimum number of nodes. Nodes 2 and 3 can be terminated by the Cluster Autoscaler / Karpenter, reducing infrastructure costs.
