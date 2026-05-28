# 02 - Kubernetes Service Architecture

A Service is an abstract way to expose an application running on a set of Pods as a network service. It provides a stable IP address (ClusterIP) and DNS name, shielding clients from the ephemeral nature of individual Pods.

## Structural Relationship

```mermaid
graph TD
    %% Styling
    classDef svc fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef ctrl fill:#313244,stroke:#f9e2af,stroke-width:2px,color:#cdd6f4;
    classDef ep fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef pod fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;

    Client[Client Pod / External User] -->|1. Request to Stable IP / DNS| Service[Service Spec <br> Name: web-backend-service <br> ClusterIP: 10.96.14.22 <br> Selector: app=web-backend]:::svc

    subgraph ControlPlane [Kubernetes Control Plane]
        EndpointsCtrl[Endpoints Controller]:::ctrl
    end

    EndpointsCtrl -->|2. Watches Labels| Pods
    EndpointsCtrl -->|3. Updates Backend List| Endpoints[Endpoints Resource <br> Name: web-backend-service <br> IPs: 10.244.1.5:8080, 10.244.1.6:8080, 10.244.2.12:8080]:::ep

    Service -.->|Reads Backend IPs| Endpoints

    subgraph Pods [Target Pod Replicas]
        Pod1[Pod A <br> Labels: app=web-backend <br> IP: 10.244.1.5]:::pod
        Pod2[Pod B <br> Labels: app=web-backend <br> IP: 10.244.1.6]:::pod
        Pod3[Pod C <br> Labels: app=web-backend <br> IP: 10.244.2.12]:::pod
    end

    Endpoints -.->|Directs Traffic to| Pod1
    Endpoints -.->|Directs Traffic to| Pod2
    Endpoints -.->|Directs Traffic to| Pod3
```

### Key Concepts
* **Selector**: The label query used by the service to identify target pods (`app=web-backend`).
* **Endpoints**: A separate API object automatically created by Kubernetes that tracks the actual, healthy IP addresses and ports of Pods matching the selector.
* **Stable Abstraction**: If Pod B dies and is replaced by Pod D (with a new IP), the Endpoints Controller automatically updates the Endpoints list, ensuring the Client continues to call the Service IP without interruption.
