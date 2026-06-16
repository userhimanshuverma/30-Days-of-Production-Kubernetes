# 📊 Day 25: Multi-Cluster Architectural Diagram Reference

This document catalogs the 12 primary structural models, networking paths, and control systems required to build a global cloud-native platform.

---

## 1. Multi-Cluster Architecture: Hub-and-Spoke vs. Mesh

This diagram contrasts the two main organizational structures for managing multiple clusters.

```mermaid
graph TD
    subgraph Hub and Spoke Model
        HC[Hub Cluster / Mgmt Plane] -->|Control Policies| C1[Spoke Cluster A]
        HC -->|Control Policies| C2[Spoke Cluster B]
        HC -->|Control Policies| C3[Spoke Cluster C]
        style HC fill:#1B4F72,stroke:#333,stroke-width:2px,color:#fff
    end

    subgraph Mesh Model (Decentralized)
        M1[Independent Cluster A] <-->|Peer-to-Peer Mesh Sync| M2[Independent Cluster B]
        M2 <-->|Peer-to-Peer Mesh Sync| M3[Independent Cluster C]
        M3 <-->|Peer-to-Peer Mesh Sync| M1[Independent Cluster A]
        style M1 fill:#145A32,stroke:#333,stroke-width:2px,color:#fff
        style M2 fill:#145A32,stroke:#333,stroke-width:2px,color:#fff
        style M3 fill:#145A32,stroke:#333,stroke-width:2px,color:#fff
    end
```

*   **Hub-and-Spoke**: Ideal for central operations. The hub runs the controllers and distributes configurations; spokes are cattle clusters that only execute workloads.
*   **Mesh Model**: Ideal for independent autonomous divisions. Every cluster is its own master and communicates with peers directly.

---

## 2. Cluster Federation Model (Karmada/OCM Controller)

This diagram shows how Karmada translates a single developer intent into customized, regional deployments.

```mermaid
graph LR
    Dev[Developer / GitOps] -->|kubectl apply| Template[Resource Template: Deployment]
    Dev -->|kubectl apply| Policy[Propagation Policy: Split 60/40]
    Dev -->|kubectl apply| Override[Override Policy: Region Envs]

    subgraph Karmada Control Loop
        Template --> Controller[Karmada Controller Manager]
        Policy --> Controller
        Override --> Controller
        Controller -->|Render & Inject| SpokeEast[Cluster-East APIServer]
        Controller -->|Render & Inject| SpokeWest[Cluster-West APIServer]
    end

    subgraph Target Execution
        SpokeEast -->|Deploys 3 Replicas| PodsE[Apps in us-east-1]
        SpokeWest -->|Deploys 2 Replicas| PodsW[Apps in us-west-2]
    end
```

---

## 3. Hybrid Cloud Topology

Connecting an on-premise private data center running bare-metal Kubernetes with AWS cloud managed EKS.

```mermaid
graph TD
    subgraph Public Cloud: AWS GKE/EKS
        EKS[AWS EKS Cluster] -->|Pod Networks| E_Pods[Scale-Out Workloads]
        RDS[AWS Aurora Global Database]
    end

    subgraph Private Cloud: On-Premise Data Center
        BareMetal[Bare-Metal Talos Cluster] -->|Pod Networks| OP_Pods[Secure Financial Processing]
        Vault[On-Premise Secret Core]
    end

    EKS <-->|DirectConnect / IPSec VPN Tunnel| BareMetal
    RDS <-->|Secure WAN Database Sync| BareMetal
```

---

## 4. Global Deployment Architecture

End-to-end request flow from a user accessing a global website to local endpoints in different continents.

```mermaid
graph TD
    User[Client Browser] -->|DNS Resolve: app.company.com| GeoDNS[Global GeoIP Server]
    GeoDNS -->|Direct to Nearest IP| User

    User -->|Traffic Route A| EdgeEast[Anycast IP Gateway: US]
    User -->|Traffic Route B| EdgeWest[Anycast IP Gateway: EU]

    subgraph Regional Clusters
        EdgeEast -->|Route| IngressEast[Ingress Controller: US Cluster]
        EdgeWest -->|Route| IngressWest[Ingress Controller: EU Cluster]
        
        IngressEast --> PodsEast[Pod Replicas: US]
        IngressWest --> PodsWest[Pod Replicas: EU]
    end
```

---

## 5. Cross-Cluster Networking (Cilium ClusterMesh vs. Submariner)

How CNI overlays allow direct, encrypted pod-to-pod network connectivity across cluster boundaries.

```mermaid
graph TD
    subgraph Cluster A (10.240.0.0/16)
        PodA[Pod A: 10.240.1.15]
    end

    subgraph Cluster B (10.241.0.0/16)
        PodB[Pod B: 10.241.2.34]
    end

    subgraph Cilium ClusterMesh Model
        PodA -->|Direct eBPF Routing| MeshRouter[ClusterMesh Gateway]
        MeshRouter -->|Encapsulated Tunnel VXLAN/Geneve| MeshRouterB[ClusterMesh Gateway B]
        MeshRouterB --> PodB
    end

    subgraph Submariner IPSec Model
        PodA -->|Route via Submariner Gateway| GatewayA[Submariner Gateway Node A]
        GatewayA -->|IPsec Encrypted Tunnel over WAN| GatewayB[Submariner Gateway Node B]
        GatewayB --> PodB
    end
```

---

## 6. Global Traffic Routing (GeoDNS Logic)

A detailed workflow showing how GeoDNS selects endpoints based on geographical distance.

```mermaid
sequenceDiagram
    autonumber
    actor User as Client in Paris
    participant DNS as Route53 GeoDNS
    participant G_LB as Global Load Balancer
    participant E_LB as EU Ingress (Frankfurt)
    participant U_LB as US Ingress (Virginia)

    User->>DNS: Resolve app.company.com
    Note over DNS: Inspect client resolver IP (GeoIP lookup)<br/>Paris matches Europe
    DNS-->>User: Return 192.0.2.99 (Frankfurt Target IP)
    User->>G_LB: Send HTTPS Request
    G_LB->>E_LB: Route to European Gateway
    E_LB-->>User: Return HTTP 200 OK (Served from Frankfurt)
```

---

## 7. Disaster Recovery Architecture (Active-Passive Sync)

How state and resources are backed up and restored to a cold or warm standby cluster.

```mermaid
graph TD
    subgraph Primary Cluster (Active)
        AppP[Active App Workloads] -->|Write State| DBP[Primary Database]
        GitP[ArgoCD Sync State]
    end

    subgraph Backup Storage
        S3[S3 Encrypted Object Store]
    end

    subgraph Standby Cluster (Passive)
        DBPassive[Standby Database]
        AppStandby[Passive Replicas scaled to 0]
    end

    DBP -->|Continuous Async Replication| DBPassive
    AppP -->|Velero Backup manifests| S3
    S3 -->|Scheduled Restore dry-runs| StandbyCluster[Standby Cluster Admin]
```

---

## 8. Active-Active Cluster Replication

Two clusters running concurrently, managing synchronous database replication to prevent data divergence.

```mermaid
graph TD
    subgraph Cluster US-East
        LB_East[Load Balancer East] --> App_East[App Instances East]
        App_East --> DB_East[(CockroachDB Node A)]
    end

    subgraph Cluster US-West
        LB_West[Load Balancer West] --> App_West[App Instances West]
        App_West --> DB_West[(CockroachDB Node B)]
    end

    DB_East <-->|Raft Consensus Replication over WAN| DB_West
    style DB_East fill:#E67E22,stroke:#333,color:#fff
    style DB_West fill:#E67E22,stroke:#333,color:#fff
```

---

## 9. Active-Passive Clusters (DNS Routing Weight)

Traffic distribution weights configured to stand up warm reserves.

```mermaid
graph TD
    User[Web Client] -->|Request app.com| DNS[DNS GSLB]
    DNS -->|Weight: 100%| ClusterA[Cluster US-East1: Active Primary]
    DNS -->|Weight: 0% (Offline)| ClusterB[Cluster US-West2: Passive Warm Standby]

    ClusterA -->|Database Replication stream| ClusterB
    style ClusterA fill:#1E8449,color:#fff
    style ClusterB fill:#95A5A6,color:#fff
```

---

## 10. Multi-Region Failover Sequence

A step-by-step failure resolution flow when a regional data center goes completely dark.

```mermaid
sequenceDiagram
    autonumber
    actor User as Users Worldwide
    participant GSLB as Global Load Balancer / DNS
    participant ClusterUS as US-East Cluster (Degraded)
    participant ClusterEU as EU-West Cluster (Healthy)
    participant HealthCheck as GSLB Health Prober

    User->>GSLB: Request app.com
    GSLB->>ClusterUS: Route traffic to US (Normal state)
    Note over ClusterUS: Network card switch burns out.<br/>US Cluster goes completely offline.
    HealthCheck->>ClusterUS: Ping HTTP probe (Endpoint check)
    HealthCheck->>ClusterUS: Retry failed 3 times.
    Note over HealthCheck: US Cluster marked DEAD.
    HealthCheck->>GSLB: Withdraw US IP from DNS Pools.
    GSLB->>User: Route next requests to EU IP.
    User->>ClusterEU: Connect to EU-West Cluster.
    Note over User: User experiences 5-second recovery lag, then operates normally.
```

---

## 11. Platform Management Architecture (GitOps Engine)

How platform teams manage and maintain drift correction across a global fleet of 100+ clusters.

```mermaid
graph TD
    Git[Git Repository: infra-config] -->|Webhook| Argo[ArgoCD Management Cluster]
    
    subgraph Destination Fleet
        Argo -->|Push & Sync| Cluster1[Kubernetes Cluster 1: Dev]
        Argo -->|Push & Sync| Cluster2[Kubernetes Cluster 2: Staging]
        Argo -->|Push & Sync| Cluster3[Kubernetes Cluster 3: Prod-US]
        Argo -->|Push & Sync| Cluster4[Kubernetes Cluster 4: Prod-EU]
    end

    Cluster4 -->|Local manual edit by operator| Drift[Drift Detected]
    Drift -->|Argo Auto-Heal override| Cluster4
```

---

## 12. End-to-End Global Platform Design

This diagram represents the ultimate synthesis: a global request entry pipeline combining CDN, Global Server Load Balancing, Web Application Firewall, local ingress, cross-cluster service mesh, and globally replicated databases.

```mermaid
graph TD
    Client[Global Users] -->|Query| CDN[Cloudflare CDN & Edge WAF]
    CDN -->|GeoDNS / Anycast Routing| GSLB[Global Traffic Load Balancer]

    subgraph Cluster Region A (US)
        GSLB -->|Route US users| IngressA[Nginx Ingress Controller]
        IngressA --> ServiceA[Order Service: Local]
        ServiceA --> PodsA[Order Pods US]
        PodsA --> Database[(CockroachDB: Master Node A)]
    end

    subgraph Cluster Region B (EU)
        GSLB -->|Route EU users| IngressB[Nginx Ingress Controller]
        IngressB --> ServiceB[Order Service: Local]
        ServiceB --> PodsB[Order Pods EU]
        PodsB --> Database
    end

    subgraph Service Mesh Interconnect
        PodsA <-->|Cilium ClusterMesh encrypted tunnels| PodsB
    end

    style Database fill:#E67E22,stroke:#333,color:#fff
```
