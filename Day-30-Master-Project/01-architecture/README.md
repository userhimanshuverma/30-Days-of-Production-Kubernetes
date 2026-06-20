# Production Platform Architecture Deep Dive

This document details the architectural decisions and topology constraints for the production-ready Kubernetes platform.

---

## 🏛️ Control Plane High Availability (HA)
In production environments (EKS, GKE, or Bare-Metal), the control plane must survive the loss of master nodes without dropping traffic or database transactions.

```
                  ┌──────────────────────┐
                  │ External Load Balancer│
                  └──────────┬───────────┘
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
     ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
     │Master Node 1│  │Master Node 2│  │Master Node 3│
     │(API Server) │  │(API Server) │  │(API Server) │
     └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
            └────────────────┼────────────────┘
                             ▼
                    ┌────────────────┐
                    │  HA etcd Ring  │
                    │ (3-Node Cluster│
                    │  for Consensus)│
                    └────────────────┘
```

1.  **Etcd Consensus**: Etcd uses the Raft protocol. A minimum of 3 nodes is required to survive 1 failure ($N = 2F + 1$, where $N$ is the cluster size and $F$ is the maximum number of tolerable node failures).
2.  **API Server Redundancy**: API servers are stateless and fronted by an external Layer 4 Load Balancer routing TLS traffic on port `6443`.
3.  **Controller Manager & Scheduler Leader Election**: Only one controller manager and scheduler can actively execute resource loops at a time. Active instances lock the state via lease resources in `kube-system`. If the leader fails, secondary instances pick up the lease.

---

## 🔒 Security Isolation (Zero-Trust Model)
The cluster enforces multi-tenant boundary isolation using the following controls:
*   **Network Policies**: Deny-all ingress and egress traffic by default. Explicit paths allow connections only between verified layers. For instance, the `monitoring` namespace is permitted to query `/metrics` endpoints, but standard worker pods cannot reach database storage pools directly.
*   **Access Control (RBAC)**: Custom ServiceAccounts bind only to specific roles (e.g. the FastAPI service account can publish events to Kafka topics and write transaction logs to PostgreSQL, but cannot list, inspect, or delete other namespaces).

---

## 🏎️ Telemetry Scrape Loops & Pipelines
Distributed telemetry is handled by the **OpenTelemetry (OTel) Collector** running as a DaemonSet:
1.  **Metrics**: Scraped by Prometheus Operator using `ServiceMonitors` that filter pods by labels.
2.  **Logs**: Promtail aggregates stdout logs on the host filesystem (`/var/log/pods`) and pushes them to Loki.
3.  **Traces**: The application imports the OTel SDK to wrap HTTP handlers. Tracing spans are exported directly to the OTel Collector, which batches, parses, and sends them to Tempo for trace indexing.
