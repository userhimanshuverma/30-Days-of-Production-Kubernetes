# 10 - Endpoint Mapping & EndpointSlices

When Pods scale up, scale down, or fail health checks, their status must be propagated to Services. This mapping is managed by the EndpointSlice Controller.

## Endpoint vs. EndpointSlice Architecture

```mermaid
graph TD
    %% Styling
    classDef api fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef legacy fill:#f87171,stroke:#b91c1c,stroke-width:2px,color:#cdd6f4;
    classDef modern fill:#4ade80,stroke:#15803d,stroke-width:2px,color:#cdd6f4;
    classDef node fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;

    APIServer[kube-apiserver]:::api

    subgraph LegacyEndpoints [Legacy Endpoints Model (Scales poorly)]
        EndpointsResource[Endpoints Object <br> Name: web-backend-service <br> Holds ALL IPs: 10.244.1.1, 1.2, 1.3 ... 1.1000]:::legacy
        APIServer --> EndpointsResource
        EndpointsResource -->|Sends whole object on any change| Node1A[Node 1 kube-proxy]:::node
        EndpointsResource -->|Huge bandwidth consumption| Node2A[Node 2 kube-proxy]:::node
    end

    subgraph ModernEndpointSlices [Modern EndpointSlices Model (Production Standard)]
        EPS1[EndpointSlice 1 <br> IPs: 1.1 to 1.100]:::modern
        EPS2[EndpointSlice 2 <br> IPs: 1.101 to 1.200]:::modern
        EPS3[EndpointSlice 3 <br> IPs: 1.201 to 1.300]:::modern
        
        APIServer --> EPS1
        APIServer --> EPS2
        APIServer --> EPS3
        
        EPS1 -->|Only send slice 1 update if 1.5 changes| Node1B[Node 1 kube-proxy]:::node
        EPS1 -->|Massive network/CPU savings| Node2B[Node 2 kube-proxy]:::node
    end
```

### Why EndpointSlices Matter in Production
* **The Legacy Problem**: In the traditional `Endpoints` resource model, all backing Pod IPs are stored in a single object. If you have 2,000 backend Pods (common in large-scale deployments) and a single Pod restarts:
  1. The API server updates the Endpoints object.
  2. The entire 2,000-IP object is sent via watch streams to **every single worker node** in the cluster.
  3. This generates gigabytes of network traffic and spikes the CPU on all nodes.
* **The EndpointSlice Solution**: Introduced to solve this "endpoint explosion". It limits each EndpointSlice resource to a maximum of 100 endpoints by default. When an endpoint changes, only the specific slice containing that endpoint is updated and sent to kube-proxy, reducing data transfer size by up to 99%.
