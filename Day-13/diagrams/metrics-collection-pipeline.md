# 📐 Metrics Collection Pipeline

This diagram shows the path that resource metrics take from raw Linux cgroups to the autoscaler control loop.

```mermaid
flowchart LR
    subgraph Host ["Worker Node Host"]
        cgroups["Linux cgroups<br/>(v1/v2 files)"]
        Kubelet["Kubelet Daemon<br/>(Summary API /stats)"]
    end

    subgraph Cluster ["Cluster Control Plane"]
        MetricsServer["Metrics Server<br/>(apis/metrics.k8s.io)"]
        Prometheus["Prometheus / Adapter<br/>(apis/custom.metrics.k8s.io)"]
        APIServer["Kubernetes API Server"]
        HPA["HPA Controller"]
    end

    cgroups -->|Read metrics| Kubelet
    Kubelet -->|Scraped by HTTP /stats/summary| MetricsServer
    Kubelet -->|Scraped by HTTP /metrics/cadvisor| Prometheus
    
    MetricsServer -->|Registered Aggregator| APIServer
    Prometheus -->|Custom Metrics Adapter| APIServer
    
    APIServer -->|Serves metrics| HPA
    HPA -->|Evaluates scale rules| HPA

    style Host fill:#EAECEE,stroke:#5D6D7E,stroke-width:2px
    style Cluster fill:#EAFAF1,stroke:#27AE60,stroke-width:2px
    style Kubelet fill:#5DADE2,stroke:#2471A3,color:#fff
    style MetricsServer fill:#F39C12,stroke:#B9770E,color:#fff
    style Prometheus fill:#E74C3C,stroke:#922B21,color:#fff
    style HPA fill:#8E44AD,stroke:#6C3483,color:#fff
```

### Explanatory Summary
1. **Linux kernel Level:** The underlying Linux kernel tracks CPU shares, throttling, and memory resident set size (RSS) via container cgroups.
2. **Kubelet Exposure:** The **Kubelet** consolidates these metrics. It exposes them in two formats:
   * `/stats/summary` (JSON) for `metrics-server`.
   * `/metrics/cadvisor` (Prometheus exposition format) for scraping.
3. **Control Plane Aggregation:** 
   * **Metrics Server** aggregates basic CPU/Memory resource metrics.
   * **Prometheus + Prometheus Adapter** converts application custom metrics (e.g. connections, requests/second) into Kubernetes API queries.
4. **API Registration:** Both endpoints are registered as API Service extensions so that they can be accessed natively through the main API Server.
5. **Autoscaler Consumption:** The HPA queries the API Server directly, bypassing the need to scrape nodes or metrics agents directly.
