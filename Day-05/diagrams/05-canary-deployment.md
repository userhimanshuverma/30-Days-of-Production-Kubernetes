# 05 - Canary Deployment Strategy

This diagram illustrates how a label-based Canary Deployment routes incoming traffic. The Service routes traffic to both Deployments by selecting their common label (`app: payment-processor-canary`). The traffic split ratio is determined by the proportion of v1 vs. v2 pods (3:1, routing 25% of requests to the canary).

```mermaid
graph TD
    %% Styling
    classDef svc fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef pod_v1 fill:#1e1e2e,stroke:#94e2d5,stroke-width:2px,color:#cdd6f4;
    classDef pod_v2 fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef traffic fill:#181825,stroke:#f38ba8,stroke-width:2px,color:#cdd6f4;

    Traffic[Incoming Client Traffic]:::traffic -->|100% Request Load| Service[Service: selector: app=payment-processor-canary]:::svc
    
    subgraph V1_Deploy [Deployment v1.0.0 (Stable - 3 Replicas)]
        Pod1[Pod: canary-v1-aaa]:::pod_v1
        Pod2[Pod: canary-v1-bbb]:::pod_v1
        Pod3[Pod: canary-v1-ccc]:::pod_v1
    end

    subgraph V2_Deploy [Deployment v2.0.0 (Canary - 1 Replica)]
        PodCanary[Pod: canary-v2-xxx]:::pod_v2
    end

    Service -->|25% Load| Pod1
    Service -->|25% Load| Pod2
    Service -->|25% Load| Pod3
    Service -->|25% Load (Canary)| PodCanary

    %% Legend
    style V1_Deploy fill:#181825,stroke:#94e2d5,stroke-dasharray: 5 5
    style V2_Deploy fill:#181825,stroke:#cba6f7,stroke-dasharray: 5 5
```
