# 06 - Blue/Green Deployment Strategy

This diagram shows the Blue/Green deployment strategy. The Service selector points to `color: blue` initially. The Green environment runs in isolation for smoke testing. To cut over, the Service is updated to select `color: green`, resulting in instant traffic redirection.

```mermaid
graph TD
    %% Styling
    classDef active fill:#1e1e2e,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef stage fill:#1e1e2e,stroke:#f9e2af,stroke-width:2px,color:#cdd6f4;
    classDef svc fill:#313244,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    
    Traffic[Incoming Client Traffic] --> Service[Service: selector: app=payment-processor-bg <br> color: blue -> color: green]:::svc

    subgraph Blue [Blue Environment (Stable - Active)]
        direction LR
        PodB1[Pod: blue-aaa]:::active
        PodB2[Pod: blue-bbb]:::active
        PodB3[Pod: blue-ccc]:::active
    end

    subgraph Green [Green Environment (Release Candidate - Idle/Testing)]
        direction LR
        PodG1[Pod: green-xxx]:::stage
        PodG2[Pod: green-yyy]:::stage
        PodG3[Pod: green-zzz]:::stage
    end

    Service -->|1. Active Routing (Before Patch)| Blue
    Service -.->|2. Switched Routing (After Patch)| Green

    style Blue fill:#1e1e2e,stroke:#89b4fa,stroke-width:1px
    style Green fill:#1e1e2e,stroke:#f9e2af,stroke-width:1px
```
