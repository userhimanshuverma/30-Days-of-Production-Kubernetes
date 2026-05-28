# 📊 Day 6 Visual Architecture Hub: Kubernetes Services & Networking

This directory contains high-fidelity visual diagrams representing the internal mechanics, packet flows, and routing algorithms of Kubernetes Services and Networking.

---

## 🗺️ Diagrams Index

| # | Diagram | Target Path | Core Concept |
|---|---|---|---|
| 01 | **Pod-to-Pod Communication** | [01-pod-to-pod.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/01-pod-to-pod.md) | Veth pairs, bridges, and cross-node overlay/routing paths |
| 02 | **Service Architecture** | [02-service-architecture.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/02-service-architecture.md) | Relationship between Services, Selectors, and Endpoints |
| 03 | **ClusterIP Packet Flow** | [03-clusterip-packet-flow.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/03-clusterip-packet-flow.md) | Virtual IP routing, interception, and client-side DNAT |
| 04 | **NodePort Traffic Routing** | [04-nodeport-routing.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/04-nodeport-routing.md) | Port bindings and the double-NAT (SNAT) external hop problem |
| 05 | **LoadBalancer Service Workflow** | [05-loadbalancer-workflow.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/05-loadbalancer-workflow.md) | CCM interaction and `externalTrafficPolicy` (Cluster vs Local) |
| 06 | **DNS Resolution Flow in CoreDNS** | [06-dns-resolution-flow.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/06-dns-resolution-flow.md) | Search path traversal, ndots:5 latency penalty, and upstream forwards |
| 07 | **kube-proxy Internals** | [07-kube-proxy-internals.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/07-kube-proxy-internals.md) | API watch loop, controller reconciliation, and data path updates |
| 08 | **iptables Packet Traversal Path** | [08-iptables-routing.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/08-iptables-routing.md) | Traversal of custom Netfilter chains and statistics balancing |
| 09 | **IPVS Routing Architecture** | [09-ipvs-architecture.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/09-ipvs-architecture.md) | Hash tables lookup performance vs sequential chains scanning |
| 10 | **Endpoint Mapping & EndpointSlices** | [10-endpoint-mapping.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/10-endpoint-mapping.md) | Solving "endpoint explosion" in large scale clusters |
| 11 | **Cross-Node Networking** | [11-cross-node-networking.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/11-cross-node-networking.md) | VXLAN overlay encapsulation vs BGP / native routing |
| 12 | **Service Discovery Workflow** | [12-service-discovery.md](file:///d:/30_Days_of_Production_Kubernetes/Day-06/diagrams/12-service-discovery.md) | DNS lookup paths vs legacy environment variable injection |

---

## 🎨 Core Diagram Previews

### 1. Pod-to-Pod Communication (Same Node & Cross-Node)
```mermaid
graph TD
    classDef pod fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef netDev fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef node fill:#181825,stroke:#a6e3a1,stroke-dasharray: 5 5,stroke-width:2px,color:#cdd6f4;

    subgraph Node1 [Worker Node 1]
        PodA[Pod A <br> IP: 10.244.1.5]:::pod -->|eth0| VethA[vethA]:::netDev
        PodB[Pod B <br> IP: 10.244.1.6]:::pod -->|eth0| VethB[vethB]:::netDev
        VethA <--> Bridge1[cbr0 / Bridge]:::netDev
        VethB <--> Bridge1
        Bridge1 <--> Eth1[eth0 / Physical NIC]:::netDev
    end

    subgraph Node2 [Worker Node 2]
        Bridge2[cbr0 / Bridge]:::netDev <--> Eth2[eth0 / Physical NIC]:::netDev
        VethC[vethC]:::netDev <--> Bridge2
        VethC -->|eth0| PodC[Pod C <br> IP: 10.244.2.12]:::pod
    end

    Eth1 <-->|Physical Network / Overlay Tunnel| Eth2
```

### 2. Service-to-Pod Endpoints Mapping
```mermaid
graph TD
    classDef svc fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef ep fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef pod fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;

    Client[Client Pod] -->|ClusterIP: 10.96.14.22| Service[Service: web-backend-service]:::svc
    Service -.->|Queries| Endpoints[Endpoints List: 10.244.1.5:8080, 10.244.1.6:8080, 10.244.2.12:8080]:::ep
    Endpoints -.->|Directs Traffic| Pod1[Pod A]:::pod
    Endpoints -.->|Directs Traffic| Pod2[Pod B]:::pod
    Endpoints -.->|Directs Traffic| Pod3[Pod C]:::pod
```
