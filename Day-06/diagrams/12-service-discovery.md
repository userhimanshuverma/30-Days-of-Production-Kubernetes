# 12 - Service Discovery Workflow

Kubernetes provides two primary mechanisms for discovery: **DNS-based** and **Environment Variables**.

## How Services are Discovered

```mermaid
graph TD
    %% Styling
    classDef pod fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef discovery fill:#313244,stroke:#f9e2af,stroke-width:2px,color:#cdd6f4;
    classDef svc fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;

    Pod[Client Pod Startup]:::pod --> DiscoveryType{Discovery Method}
    
    %% DNS Flow
    DiscoveryType -->|Method A: DNS Lookup <br> Dynamic & Preferred| DNS_Query[Query: web-backend-service]:::discovery
    DNS_Query -->|CoreDNS resolves name| ServiceIP[Resolve to ClusterIP: 10.96.14.22]:::discovery
    ServiceIP -->|Routes to backends| Service[Target Service]:::svc

    %% Env Var Flow
    DiscoveryType -->|Method B: Environment Variables <br> Legacy & Static| Env_Vars[Read env vars injected <br> at container startup]:::discovery
    Env_Vars -->|Read: WEB_BACKEND_SERVICE_SERVICE_HOST <br> WEB_BACKEND_SERVICE_SERVICE_PORT| StaticIP[Target IP: 10.96.14.22]:::discovery
    StaticIP --> Service
```

### 1. DNS-Based Service Discovery (Modern Standard)
* When a Service is created, a DNS record is automatically registered in CoreDNS: `<service-name>.<namespace>.svc.cluster.local`.
* This resolves to the Service's ClusterIP.
* **Pros**: Dynamic. If a service is created *after* the Pod started, the Pod can still resolve it instantly.

### 2. Environment Variables (Legacy)
* When a Pod is created, the Kubelet automatically injects environment variables for every active Service running in that same namespace.
* If a service is named `web-backend-service`, the following env vars are injected:
  ```bash
  WEB_BACKEND_SERVICE_SERVICE_HOST=10.96.14.22
  WEB_BACKEND_SERVICE_SERVICE_PORT=80
  WEB_BACKEND_SERVICE_PORT=tcp://10.96.14.22:80
  WEB_BACKEND_SERVICE_PORT_80_TCP=tcp://10.96.14.22:80
  ```
* **Critical Flaw**: **Order of Creation Dependency**. If `web-backend-service` is created *after* the client Pod, the client Pod will not have these environment variables injected. Therefore, always rely on DNS-based resolution in production.
