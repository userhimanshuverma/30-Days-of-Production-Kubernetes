# Multi-Cluster Logging Architecture

This hub-and-spoke architecture diagram shows how logs from multiple geographic or logical Kubernetes clusters are aggregated into a single centralized observability cluster.

```mermaid
flowchart TD
    subgraph SpokeCluster1 ["Edge Cluster: EU-West"]
        FB1[Fluent Bit DaemonSet]
        AppA[Frontend Pod] --> FB1
    end

    subgraph SpokeCluster2 ["Edge Cluster: US-East"]
        FB2[Fluent Bit DaemonSet]
        AppB[Payment Pod] --> FB2
    end

    subgraph TransitLayer ["Security & Routing"]
        Ingress[API Gateway / Ingress Controller]
    end

    subgraph HubCluster ["Central Observability Cluster"]
        LokiCentral[Loki Ingest Cluster]
        GrafanaCentral[Grafana Dashboard]
        
        LokiCentral --> GrafanaCentral
    end

    FB1 -->|HTTP HTTPS Mutual TLS + cluster=eu-west| Ingress
    FB2 -->|HTTP HTTPS Mutual TLS + cluster=us-east| Ingress
    
    Ingress --> LokiCentral
```

### Key Multi-Cluster Patterns:
* **Mutual TLS (mTLS):** Ensures logs are encrypted in transit over public networks.
* **Cluster Tagging:** The shipper injects a static cluster identifier label (e.g. `cluster="eu-west"`) at the edge, allowing users to query logs globally or filter by specific environments.
* **Local Buffer Gateways:** If the central hub goes offline, edge collectors buffer logs locally to prevent data loss.
