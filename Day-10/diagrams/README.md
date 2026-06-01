# 📊 Ingress & Traffic Routing Diagrams

Visual blueprints illustrating how external traffic is routed, secured, and proxy-forwarded within a production Kubernetes cluster.

---

## 1. External Traffic Flow
This diagram traces the flow of a client's request from DNS resolution through the cloud infrastructure down to the target pod inside the Kubernetes cluster.

```mermaid
graph TD
    Client["Client Browser"] -->|1. DNS Lookup: academy.internal| DNS["DNS Server (Route53/Cloudflare)"]
    DNS -->|2. Returns LB IP| Client
    Client -->|3. HTTPS Request (Port 443)| CloudLB["Cloud Load Balancer (NLB/ALB)"]
    CloudLB -->|4. Routes to NodePort| K8sNode1["K8s Worker Node 1 (IP: 10.0.1.10)"]
    CloudLB -->|4. Routes to NodePort| K8sNode2["K8s Worker Node 2 (IP: 10.0.1.11)"]
    
    subgraph "Kubernetes Cluster ClusterIP Range"
        K8sNode1 -->|Port 32080/32443| IngressPod1["NGINX Ingress Pod (Replica 1)"]
        K8sNode2 -->|Port 32080/32443| IngressPod2["NGINX Ingress Pod (Replica 2)"]
        
        IngressPod1 -->|5. Routes directly to Pod IP| PodA["Order API Pod (10.244.1.35)"]
        IngressPod2 -->|5. Routes directly to Pod IP| PodB["Order API Pod (10.244.2.82)"]
    end

    style Client fill:#3F51B5,stroke:#303F9F,stroke-width:2px,color:#fff
    style CloudLB fill:#FF5722,stroke:#E64A19,stroke-width:2px,color:#fff
    style IngressPod1 fill:#9C27B0,stroke:#7B1FA2,stroke-width:2px,color:#fff
    style IngressPod2 fill:#9C27B0,stroke:#7B1FA2,stroke-width:2px,color:#fff
    style PodA fill:#4CAF50,stroke:#388E3C,stroke-width:2px,color:#fff
    style PodB fill:#4CAF50,stroke:#388E3C,stroke-width:2px,color:#fff
```

---

## 2. Service vs Ingress Architecture
Compare the cost-inefficient "LoadBalancer-for-everything" approach with the unified "Ingress Controller" pattern.

```mermaid
graph TD
    subgraph "A. Inefficient LoadBalancer Service Pattern (High Cost)"
        Client1["Client"] --> LB1["Cloud LB 1 ($$$)"] --> SvcA["Frontend Service (LoadBalancer)"] --> PodA1["Frontend Pod"]
        Client1 --> LB2["Cloud LB 2 ($$$)"] --> SvcB["Order Service (LoadBalancer)"] --> PodB1["Order Pod"]
    end

    subgraph "B. Unified Ingress Pattern (Cost-Optimized & Secure)"
        Client2["Client"] --> LBU["Single Cloud LB ($)"] --> IngressCtrl["Ingress Controller (NGINX)"]
        IngressCtrl -->|Host: academy.internal| SvcC["Frontend Service (ClusterIP)"] --> PodC1["Frontend Pod"]
        IngressCtrl -->|Path: /api/orders| SvcD["Order Service (ClusterIP)"] --> PodD1["Order Pod"]
    end

    style LB1 fill:#ffcdd2,stroke:#e53935
    style LB2 fill:#ffcdd2,stroke:#e53935
    style LBU fill:#c8e6c9,stroke:#43a047
    style IngressCtrl fill:#e1bee7,stroke:#8e24aa
```

---

## 3. NGINX Ingress Controller Architecture
The interaction between the Control Plane (watching resources via the API server) and the Data Plane (parsing configuration and proxying traffic).

```mermaid
graph LR
    subgraph "Control Plane (Go Loop)"
        APIServer["Kubernetes API Server"] <-->|Watches Ingress, Services, Endpoints| GoController["NGINX Ingress Controller (Go)"]
        GoController -->|Generates Configuration| ConfigTemplate["nginx.conf Template"]
    end

    subgraph "Data Plane (Nginx / OpenResty)"
        ConfigTemplate -->|Triggers Dynamic Update| NginxCore["NGINX Master Process"]
        NginxCore -->|Spawns / Configures| Workers["NGINX Worker Processes"]
        LuaShared["Lua Shared Memory (lua-nginx-module)"] -->|Dynamic Endpoint Updates without Reload| Workers
        GoController -->|Injects Endpoints directly| LuaShared
    end

    IncomingTraffic["Client HTTP/S Traffic"] ====> Workers
    Workers ====> BackendPods["Backend Application Pods"]

    style APIServer fill:#e0f7fa,stroke:#00acc1
    style GoController fill:#ede7f6,stroke:#5e35b1
    style Workers fill:#fff3e0,stroke:#fb8c00
```

---

## 4. TLS Termination Workflow
This sequence diagram shows how HTTPS encryption is terminated at the Ingress controller, and subsequent communications are forwarded within the cluster.

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client Browser
    participant Ingress as Ingress Controller (NGINX)
    participant K8sSecret as TLS Secret (academy-tls-secret)
    participant Pod as Backend Pod (Plaintext HTTP)

    Note over Client, Ingress: TLS Handshake (Decryption Edge)
    Client->>Ingress: Client Hello (Supported Ciphers, TLS version)
    Ingress->>K8sSecret: Fetches private key & certificate cert
    K8sSecret-->>Ingress: Returns cert data
    Ingress->>Client: Server Hello (Sends Certificate & Selected Cipher)
    Client->>Client: Validates Cert Chain against Trust Store
    Client->>Ingress: Key Exchange & Session Key Negotiation
    Ingress->>Client: Handshake Completed (Encrypted Session Active)
    
    Note over Client, Ingress: Encrypted Channel (HTTPS)
    Client->>Ingress: GET /api/v1/orders (Encrypted payload)
    
    Note over Ingress: Decrypts payload using Session Key
    
    Note over Ingress, Pod: Cluster Internal Network (HTTP)
    Ingress->>Pod: GET /healthz (Plaintext HTTP + Forwarded Headers)
    Pod-->>Ingress: HTTP 200 OK (Plaintext Response)
    
    Note over Ingress: Encrypts payload using Session Key
    Ingress-->>Client: HTTP 200 OK (Encrypted payload)
```

---

## 5. Reverse Proxy Architecture & Header Mutation
See how the Ingress proxy acts as an intermediary, injecting client context metadata into headers before dispatching upstream.

```mermaid
graph LR
    Client["Client\nIP: 192.168.10.50\nUser-Agent: Chrome"] -->|1. GET /api/v1/orders| Ingress["Ingress Controller\nIP: 10.0.1.100\nGenerates Request-ID: req-abc123"]
    
    subgraph "Header Injection"
        Ingress -->|2. Proxied Request| Backend["Backend Pod\nIP: 10.244.1.35"]
    end
    
    note["<b>Headers Injected by Ingress:</b><br/>- Host: academy.internal<br/>- X-Real-IP: 192.168.10.50<br/>- X-Forwarded-For: 192.168.10.50, 10.0.1.100<br/>- X-Forwarded-Proto: https<br/>- X-Request-ID: req-abc123"]
    Ingress -.-> note
    note -.-> Backend
```

---

## 6. Path-Based Routing
Routing requests to different microservices based on the URL path structure.

```mermaid
graph TD
    Request["GET academy.internal/api/v1/orders"] --> Ingress["Ingress Controller"]
    
    Ingress -->|Matches /api/v1/orders| OrderSvc["order-api-svc (ClusterIP)"]
    Ingress -->|Matches /api/v1/users| UserSvc["user-api-svc (ClusterIP)"]
    Ingress -->|Matches default /| FrontendSvc["frontend-svc (ClusterIP)"]

    OrderSvc --> Pod1["order-api-pod-0"]
    UserSvc --> Pod2["user-api-pod-0"]
    FrontendSvc --> Pod3["frontend-pod-0"]

    style OrderSvc fill:#ffe0b2,stroke:#f57c00
    style UserSvc fill:#e8f5e9,stroke:#388e3c
    style FrontendSvc fill:#e1f5fe,stroke:#0288d1
```

---

## 7. Host-Based Routing
Routing requests to completely different services using the incoming HTTP Host header.

```mermaid
graph TD
    ReqA["GET /index.html\nHost: academy.internal"] --> Ingress["Ingress Controller"]
    ReqB["GET /users\nHost: api.academy.internal"] --> Ingress
    
    Ingress -->|Host: academy.internal| FrontendSvc["frontend-svc (ClusterIP)"]
    Ingress -->|Host: api.academy.internal| APIWSvc["user-api-svc (ClusterIP)"]
    
    FrontendSvc --> Pod1["frontend-pod-1"]
    APIWSvc --> Pod2["user-api-pod-1"]

    style FrontendSvc fill:#e1f5fe,stroke:#0288d1
    style APIWSvc fill:#e8f5e9,stroke:#388e3c
```

---

## 8. Multi-Service Ingress Topology
Single configuration resource managing multiple hosts and routing paths.

```mermaid
graph TD
    IngressResource["Ingress Manifest: main-ingress"]
    
    subgraph "academy.internal Rules"
        IngressResource --> PathF["Path: / (Prefix)"] --> FrontendSvc["frontend-svc:80"]
        IngressResource --> PathO["Path: /api/v1/orders"] --> OrderSvc["order-api-svc:80"]
        IngressResource --> PathU["Path: /api/v1/users"] --> UserSvc["user-api-svc:80"]
    end
    
    subgraph "api.academy.internal Rules"
        IngressResource --> PathAPI1["Path: /orders"] --> OrderSvc
        IngressResource --> PathAPI2["Path: /users"] --> UserSvc
    end
```

---

## 9. Request Lifecycle Timeline
A millisecond-resolution journey of a single packet starting at the client socket down to backend processing.

```mermaid
gantt
    title Request Lifecycle Timeline
    dateFormat  S
    axisFormat %L ms
    
    section Client
    DNS Resolution              :active, dns, 0, 15
    TCP Handshake (SYN/ACK)    :active, tcp, 15, 35
    TLS Handshake Negotiation   :active, tls, 35, 75
    Send HTTP Request           :active, req, 75, 80
    
    section Ingress Controller
    Parse Headers & Match Rules:crit, parse, 80, 83
    Lookup Backend Endpoint IP :crit, lookup, 83, 84
    Forward Request Upstream   :crit, proxy, 84, 88
    
    section Pod Backend
    Process Application Logic  :active, app, 88, 120
    Write JSON Response        :active, resp, 120, 122
    
    section Network Return
    Transfer Bytes to Client   :active, ret, 122, 140
```

---

## 10. DNS -> Ingress -> Service -> Pod OSI/Layer Flow
How the network resolution shifts layer responsibilities down the networking stack.

```mermaid
graph TD
    subgraph "Layer 7 (Application)"
        DNS["DNS: Hostname academy.internal"]
        HttpHost["HTTP Host Header: Host: academy.internal"]
        HttpPath["HTTP Path Routing: /api/v1/orders"]
    end

    subgraph "Layer 4 (Transport)"
        TCPCert["TCP Port 443 (TLS Session)"]
        ClusterIP["Service Virtual ClusterIP (IPVS/IPTables Port 80)"]
    end

    subgraph "Layer 3 (Network)"
        ExternalIP["Load Balancer Public IP (e.g. 34.120.5.12)"]
        PodIP["Pod IP (SDN/Overlay e.g. 10.244.1.35)"]
    end

    DNS -->|Resolves to| ExternalIP
    ExternalIP -->|Routes to| TCPCert
    TCPCert -->|Parsed by Nginx| HttpHost
    HttpHost -->|Matched with| HttpPath
    HttpPath -->|Routes to| ClusterIP
    ClusterIP -->|DNAT Translated to| PodIP
```

---

## 11. Production HA Ingress Controller Architecture
The gold standard for production-grade high-availability: multi-zone node pools, pod anti-affinity, and external load balancers.

```mermaid
graph TD
    Client["Client Traffic"] --> ExtLB["External Cloud Network Load Balancer (NLB)"]
    
    subgraph "Availability Zone A"
        ExtLB -->|Traffic distribution| NodeA["Worker Node A"]
        subgraph "Ingress Pod Pool A"
            NodeA --> IngressPodA["NGINX Ingress Pod (Replica 1)"]
        end
    end
    
    subgraph "Availability Zone B"
        ExtLB -->|Traffic distribution| NodeB["Worker Node B"]
        subgraph "Ingress Pod Pool B"
            NodeB --> IngressPodB["NGINX Ingress Pod (Replica 2)"]
        end
    end

    IngressPodA -->|Round-Robin| Pod1["App Pod 1 (Zone A)"]
    IngressPodA -->|Cross-Zone Failover| Pod2["App Pod 2 (Zone B)"]
    IngressPodB -->|Round-Robin| Pod2
    IngressPodB -->|Cross-Zone Failover| Pod1
    
    style ExtLB fill:#26a69a,stroke:#00695c,color:#fff
    style IngressPodA fill:#ab47bc,stroke:#4a148c,color:#fff
    style IngressPodB fill:#ab47bc,stroke:#4a148c,color:#fff
```

---

## 12. Canary Traffic Routing
Implementing blue-green or canary rollouts using Ingress annotations to split backend targets.

```mermaid
graph LR
    Client["User Requests"] --> Ingress["main-ingress (Academy Ingress)"]
    
    subgraph "NGINX Routing Decisions"
        Ingress -->|90% of Traffic\nDefault Route| SvcProd["order-api-svc (Production v1.0)"]
        Ingress -->|10% of Traffic\nAnnotation: canary-weight: 10| SvcCanary["order-api-canary-svc (Canary v1.1)"]
    end
    
    SvcProd --> Pod1["order-api-prod-0"]
    SvcCanary --> Pod2["order-api-canary-0"]

    style SvcProd fill:#bbdefb,stroke:#1e88e5
    style SvcCanary fill:#ffe0b2,stroke:#fb8c00
```
