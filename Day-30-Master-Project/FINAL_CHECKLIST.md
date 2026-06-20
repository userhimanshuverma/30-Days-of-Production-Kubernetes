# Day 30 — Graduation Checklist: Production Cloud-Native Platform

Before finalizing your submission and declaring your platform production-ready, ensure all components in the checklist below are verified and conform to the standards.

---

## 🗂️ Verification Checklist

### 1. High-Availability Cluster Setup
- [ ] Cluster consists of at least **3 control-plane nodes** (with a multi-node etcd cluster) and **3 worker nodes**.
- [ ] Nodes are distributed across simulated failure domains (Kind node configurations match).
- [ ] Control-plane components (`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`) are fully redundant.

### 2. Traffic Control & TLS Encryption
- [ ] NGINX Ingress controller is active and intercepts traffic on ports `80` and `443`.
- [ ] `cert-manager` is active in its own namespace and retrieves staging TLS certificates.
- [ ] Ingress routing files for the FastAPI service contain TLS configurations and map to valid secrets.

### 3. Identity, Access, & Security Hardening
- [ ] Calico Network Policies block all inter-namespace traffic by default (Default-Deny).
- [ ] Namespaces have explicit Allow policies matching only necessary database/messaging connections.
- [ ] ServiceAccounts are bound to custom roles with minimum permissions; no default ServiceAccounts have admin bindings.
- [ ] Secrets are loaded safely; the FastAPI service pulls credentials from external KMS mappings (mock Vault).

### 4. Stateful Services & Data Persistence
- [ ] PostgreSQL cluster (using CloudNativePG) has at least **3 replicas** running with hot standby.
- [ ] Kafka cluster (using Strimzi) has **3 brokers** and maintains broker partition replication factors.
- [ ] Storage volume claims (PVCs) bind to persistent storage classes; data persists across pod deletions.

### 5. Multi-Layer Observability
- [ ] Prometheus scrapes all core services, node exporters, and custom FastAPI application endpoints.
- [ ] Grafana display boards are imported and render live metrics (CPU, Memory, Ingress RPS, DB connections).
- [ ] Loki collects and aggregates container stdout logs; queries in Grafana can filter by namespace/pod.
- [ ] OpenTelemetry Collector gathers trace data from the FastAPI SDK and routes it to Jaeger/Tempo.

### 6. Autoscaling & Optimization
- [ ] HPA scales FastAPI Pods up during active traffic surges (e.g. k6 load test) and scales down when idle.
- [ ] VPA generates accurate CPU/Memory recommendations based on actual workload metrics.
- [ ] Karpenter NodePool is configured and active, provisioning new worker nodes for pending workloads.

### 7. Disaster Recovery & Operations
- [ ] Velero schedules exist for backing up persistent stateful database volumes.
- [ ] Multi-region active-passive failover runbook instructions are verified.
- [ ] Automated platform diagnostic shell scripts (`diagnose-platform.sh` and `validate-deployment.sh`) run with zero errors.

---

## 📊 Evaluation Rubric

| Category | Passing Criteria (Approved) | Premium / SRE Standard (Distinction) |
|---|---|---|
| **Networking** | Ingress forwards traffic to HTTP service. | HTTPS is fully enforced with auto-renewing TLS certificates via cert-manager. |
| **Security** | RBAC restricts namespace writes. | NetworkPolicies isolate DB namespaces; RBAC utilizes custom SAs; Secrets are encrypted via Vault wrappers. |
| **Observability** | Prometheus collects CPU and Memory metrics. | p95 latency tracing, transactional trace spans via OTel, Loki logging indexing, and custom alerts active. |
| **Autoscaling** | HPA scales replicas under load. | Karpenter scales control nodes up/down under resource stress; HPA metrics pull from custom Prometheus gauges. |
| **Stateful HA** | Postgres database is running as single instance. | Postgres cluster has 3 replicas with auto-failover (CNPG); Kafka runs with partition replication > 1. |
| **DR & Operations** | Manual backup instructions exist. | Automated Velero snapshots scheduling configured; failover validation script passes under simulated network cuts. |
