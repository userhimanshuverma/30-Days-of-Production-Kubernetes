# Day 30 — Master Project: Build a Real Production-Grade Cloud-Native Platform

Welcome to the grand finale of **30 Days of Production Kubernetes**! Today, you will combine every concept, pattern, tool, and architectural paradigm learned over the last 29 days to design, deploy, operate, and troubleshoot a unified production-ready cloud-native platform.

This capstone project is modeled after the industrial-scale architectures managed by platform engineering teams at tech giants like **Netflix, Uber, Spotify, Airbnb, and Google**.

---

## 🗺️ How the Course Phases Connect

A production-grade cloud-native platform is not just a collection of YAML files; it is a living, breathing ecosystem where all layers are deeply integrated. Here is how the five phases of **30 Days of Production Kubernetes** connect within this single capstone:

```
┌────────────────────────────────────────────────────────────────────────┐
│                      PHASE 5: REAL PRODUCTION SYSTEMS                  │
│  (Multi-region Failover, Runbooks, Platform Simulator, Load Testing)   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    PHASE 4: ADVANCED ENGINEERING                       │
│     (GitOps ArgoCD, Karpenter Autoscaling, Stateful HA Postgres/Kafka) │
└───────────────────────────────────┬────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        PHASE 3: OBSERVABILITY                          │
│     (Prometheus Metrics, Loki Logs, Tempo Traces, Otel Collector)     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   PHASE 2: RUNNING APPLICATIONS                        │
│     (Ingress Controllers, TLS Certificates, NetworkPolicies, RBAC)    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       PHASE 1: KUBERNETES FOUNDATIONS                  │
│       (Multi-master Control Plane, Worker Nodes, Pods, Services)       │
└────────────────────────────────────────────────────────────────────────┘
```

1.  **Phase 1 Foundations** provides the physical container scheduling layer (multi-node, high availability).
2.  **Phase 2 Running Applications** wraps these containers with secure routing, automated certificates (cert-manager), and isolation walls (NetworkPolicies).
3.  **Phase 3 Observability** illuminates the platform, scraping telemetry data from the application code out to Prometheus, Loki, and Tempo via the OpenTelemetry Collector.
4.  **Phase 4 Advanced Engineering** automates operations through GitOps loops (ArgoCD), cost-optimized auto-provisioning (Karpenter), and cluster state persistence (PostgreSQL/Kafka).
5.  **Phase 5 Production Systems** adds the operational resilience: automated load tests, failure simulation, failover runbooks, and continuous compliance checks.

---

## 🏗️ 12 Architecture Diagrams

### 1. Full Production Architecture
This diagram displays the complete layout of the platform, showing control planes, workers, security boundaries, and telemetry lines.

```mermaid
graph TB
    subgraph Internet [Public Internet]
        User[External Client]
    end

    subgraph AWS_or_BareMetal [Production VPC / Cloud Infrastructure]
        subgraph K8S_Cluster [High-Availability Kubernetes Cluster]
            subgraph ControlPlane [HA Control Plane - Multi-Master]
                APIServer[API Server 1/2/3]
                etcd[(HA etcd Cluster)]
                APIServer <--> etcd
            end

            subgraph IngressLayer [Routing & TLS Layer]
                IngController[NGINX Ingress Controller]
                CertMgr[cert-manager]
                LetsEncrypt[Let's Encrypt Staging]
                CertMgr <--> LetsEncrypt
            end

            subgraph SecurityBoundary [Security & Governance]
                NetPol[Calico Network Policies]
                ESO[External Secrets Operator]
                Vault[(HashiCorp Vault / External KMS)]
                ESO <--> Vault
            end

            subgraph StatefulLayer [HA Stateful Workloads]
                PGSQL[(PostgreSQL Cluster - CloudNativePG)]
                Kafka[(Kafka HA Broker Cluster - Strimzi)]
            end

            subgraph ApplicationLayer [Workload Layer]
                AIService[FastAPI AI Inference Pods]
            end

            subgraph TelemetryLayer [Centralized Observability Stack]
                OTel[OpenTelemetry Collector]
                Prom[Prometheus Operator]
                Loki[Grafana Loki]
                Tempo[Grafana Tempo]
            end
        end
    end

    User -->|HTTPS| IngController
    IngController -->|Routes Request| AIService
    AIService -->|Queries History| PGSQL
    AIService -->|Publishes Events| Kafka
    AIService -->|Telemetry SDK| OTel
    OTel -->|Metrics| Prom
    OTel -->|Logs| Loki
    OTel -->|Traces| Tempo
    Prom -->|Alerts| AlertManager[Alertmanager]
    style K8S_Cluster fill:#f9f9fb,stroke:#326ce5,stroke-width:2px
    style StatefulLayer fill:#e1f5fe,stroke:#0288d1,stroke-width:1px
    style ApplicationLayer fill:#e8f5e9,stroke:#388e3c,stroke-width:1px
    style TelemetryLayer fill:#fff3e0,stroke:#f57c00,stroke-width:1px
```

---

### 2. CI/CD GitOps Flow
How code flows from a developer's machine to the cluster using GitOps.

```mermaid
sequenceDiagram
    autonumber
    actor Developer
    participant Git as GitHub Application Repo
    participant Actions as GitHub Actions Runner
    participant Reg as Container Registry (GHCR/DockerHub)
    participant GitOps as GitHub GitOps Manifest Repo
    participant Argo as ArgoCD Controller
    participant K8s as Kubernetes Cluster

    Developer->>Git: git push new code
    Git->>Actions: Trigger CI Workflow
    Actions->>Actions: Run Linting, Security Scan, & Tests
    Actions->>Actions: Docker Build
    Actions->>Reg: Docker Push (image:tag-sha)
    Actions->>GitOps: Update deployment.yaml with image:tag-sha
    Argo->>GitOps: Poll repository for changes (Drift Detection)
    Argo->>K8s: Apply updated manifests (Reconciliation)
    K8s->>K8s: Dynamic Rolling Restart (Zero-Downtime)
```

---

### 3. Monitoring Flow
The path of metrics from targets to notifications.

```mermaid
graph LR
    subgraph Targets [Scrape Targets]
        App[FastAPI Pods]
        Node[Node Exporter]
        Kubelet[Kubelet Summary API]
    end

    subgraph Monitoring [Prometheus Stack]
        Prom[Prometheus Server]
        Rule[Alerting Rules Engine]
        AM[Alertmanager]
    end

    subgraph Notifiers [External Systems]
        Slack[Slack Channels]
        PD[PagerDuty SRE Rotation]
    end

    App & Node & Kubelet -->|Prometheus Metrics format| Prom
    Prom -->|Evaluates| Rule
    Rule -->|Trigger Active Alert| AM
    AM -->|Route Grouping & Deduplication| Slack & PD
    style Monitoring fill:#fff5eb,stroke:#f96816,stroke-width:2px
```

---

### 4. Centralized Logging Pipeline
Log collection, shipping, indexing, and visualization.

```mermaid
graph TD
    Pod1[FastAPI Container stdout] -->|Written to node disk| File[/var/log/pods/*.log]
    Pod2[Postgres Container stdout] -->|Written to node disk| File
    
    subgraph Shipping [Log Aggregator]
        Promtail[Promtail DaemonSet]
    end
    File -->|Tail & Label Logs| Promtail
    
    subgraph Storage [Log DB]
        Loki[Grafana Loki]
    end
    Promtail -->|HTTP Push Chunked Logs| Loki
    
    subgraph Visualization
        Grafana[Grafana Explorer]
    end
    Grafana -->|LogQL Queries| Loki
    style Shipping fill:#f2e6ff,stroke:#8000ff,stroke-width:1px
```

---

### 5. Metrics Pipeline
Metrics flow showing Prometheus monitoring architecture.

```mermaid
graph LR
    subgraph Pods [Workloads]
        PodA[App Replica 1]
        PodB[App Replica 2]
    end
    subgraph Scraping [Service Discovery]
        SM[ServiceMonitor Definition]
    end
    subgraph TSDB [TSDB Storage]
        Prom[Prometheus Pod]
    end
    subgraph Dashboard [Grafana UI]
        Dash[Grafana Dashboard Panels]
    end

    PodA & PodB -->|Expose /metrics| SM
    SM -->|Discovers Endpoints| Prom
    Prom -->|Polls targets every 15s| PodA & PodB
    Dash -->|PromQL Queries| Prom
```

---

### 6. Tracing Pipeline
The path of distributed span traces.

```mermaid
graph LR
    subgraph App [FastAPI Service]
        SDK[OpenTelemetry SDK]
    end
    subgraph Collector [Agent System]
        OTelColl[OpenTelemetry Collector DaemonSet]
    end
    subgraph Storage [Tracing Backend]
        Tempo[Grafana Tempo / Jaeger]
    end
    subgraph Visualization [UI]
        Grafana[Grafana Trace Viewer]
    end

    SDK -->|OLTP via gRPC/HTTP| OTelColl
    OTelColl -->|Batch Export| Tempo
    Grafana -->|TraceQL Queries| Tempo
```

---

### 7. Autoscaling Flow
How the cluster responds to horizontal resource strain.

```mermaid
graph TD
    Traffic[User Traffic Spikes] -->|RPS Increases| App[Pod Resource Consumption rises]
    App -->|Scraped by metrics-server| HPA[Horizontal Pod Autoscaler]
    HPA -->|Calculates replica count| HPA_Eval{Target CPU/RPS Exceeded?}
    HPA_Eval -->|Yes| ScaleOut[Scale replicas in Deployment]
    ScaleOut -->|Create Pods| Pending[Pods set to PENDING: No node capacity]
    Pending -->|Observed by| Karpenter[Karpenter Controller]
    Karpenter -->|Compute requirements mapping| Provision[Call Cloud API to launch worker node]
    Provision -->|New node joins cluster| Scheduled[Pending pods are scheduled & run]
    
    style HPA fill:#e8f5e9,stroke:#2e7d32
    style Karpenter fill:#e3f2fd,stroke:#1565c0
    style Pending fill:#ffebee,stroke:#c62828,stroke-width:2px
```

---

### 8. Security Architecture
The multi-layered security layout.

```mermaid
graph TB
    subgraph SecurityLayers [Platform Security Architecture]
        subgraph NetworkIsolation [Layer 1: Network Policies]
            Net[Calico Default-Deny Policy]
            AllowedTraffic[Explicit Allow rules for namespaces]
            Net --- AllowedTraffic
        end
        subgraph Authentication [Layer 2: Identity & RBAC]
            SA[Kubernetes Service Account]
            RB[RBAC RoleBinding]
            Role[RBAC Least-Privilege Role]
            SA --> RB --> Role
        end
        subgraph SecretProtection [Layer 3: Secret Management]
            ESO[External Secrets Operator]
            SecretSpec[ExternalSecret Spec]
            K8sSecret[Kubernetes Secret - Base64]
            Vault[(HashiCorp Vault / AWS Secrets Manager)]
            Vault -->|Secure Sync| ESO -->|Generates| K8sSecret
        end
    end
```

---

### 9. Data Platform Architecture
The transactional database and event pipeline.

```mermaid
graph TD
    subgraph Workload [FastAPI Web Service]
        Inference[Model Predictor Endpoint]
    end
    
    subgraph Pipeline [Event Streaming Layer]
        Kafka[Kafka HA Cluster]
        Topic[inference-events Topic]
        Kafka --- Topic
    end
    
    subgraph Database [Relational Database Layer]
        CNPG[CloudNativePG Operator]
        PGPrimary[PostgreSQL Primary Pod]
        PGReplica1[PostgreSQL Replica Pod 1]
        PGReplica2[PostgreSQL Replica Pod 2]
        PGPrimary -->|Streaming Replication| PGReplica1 & PGReplica2
    end

    Inference -->|Publish payload details| Topic
    Inference -->|Write query transaction| PGPrimary
```

---

### 10. Disaster Recovery Architecture
Active-Passive multi-region failover.

```mermaid
graph TB
    subgraph Region1 [Region: US-East-1 - ACTIVE]
        DNS1[DNS Route53 IP mapping]
        PrimaryCluster[Primary K8s Cluster]
        PGPrimary[(Postgres Primary Database)]
        BackupSchedule[Velero Scheduled Backup]
    end
    
    subgraph CloudStorage [Object Storage]
        S3Bucket[(AWS S3 Bucket / MinIO)]
    end
    
    subgraph Region2 [Region: US-West-2 - STANDBY]
        DNS2[DR Standby DNS Mapping]
        StandbyCluster[Standby K8s Cluster]
        PGReplica[(Restored Postgres DB)]
    end

    DNS1 --> PrimaryCluster
    PGPrimary -->|Continuous WAL shipping| S3Bucket
    BackupSchedule -->|Hourly snapshots| S3Bucket
    S3Bucket -->|Replication read / Restore trigger| StandbyCluster
    StandbyCluster -.->|DNS Failover Shift| DNS2
    style Region1 fill:#e2f0d9,stroke:#385723,stroke-width:2px
    style Region2 fill:#fff2cc,stroke:#7f6000,stroke-width:2px
```

---

### 11. Network Architecture
Flow of IP packets inside the cluster.

```mermaid
graph TD
    subgraph Ingress [Routing Layer]
        IngressIP[Ingress External IP]
        Service[NGINX Ingress Service NodePort/LoadBalancer]
        IngressIP --> Service
    end
    
    subgraph ClusterNet [Cluster Core CNI Network]
        NginxPod[NGINX Controller Pod]
        ServiceRouting[Kubernetes ClusterIP Service]
        AppPod1[App Container Pod 1]
        AppPod2[App Container Pod 2]
    end

    Service --> NginxPod
    NginxPod -->|Proxy Pass| ServiceRouting
    ServiceRouting -->|kube-proxy Round Robin| AppPod1 & AppPod2
```

---

### 12. End-to-End User Request Flow
What happens to a single request.

```mermaid
sequenceDiagram
    autonumber
    actor User as External Client
    participant DNS as Route53 DNS
    participant Ingress as NGINX Ingress (TLS Terminated)
    participant App as FastAPI Pod
    participant Kafka as Kafka Broker
    participant PG as PostgreSQL Primary

    User->>DNS: Resolve platform.domain.com
    DNS-->>User: Returns LoadBalancer IP Address
    User->>Ingress: HTTPS POST /api/v1/predict (Encrypted)
    Note over Ingress: Decrypts SSL payload using cert-manager TLS Secret
    Ingress->>App: Forward HTTP Request to Pod IP
    Note over App: Processes request through OpenTelemetry Interceptors
    App->>PG: Sync Write: Record input transaction
    PG-->>App: Return commit confirmation
    App->>Kafka: Async Publish: Predict event metadata
    App-->>User: Return HTTP 200 OK Response (JSON prediction output)
```

---

## 🛠️ Repository Directory Index

Here is the blueprint mapping files you will find in this repository:

```
Day-30-Master-Project/
├── 01-architecture/         # Architecture models and layout notes
│   └── README.md
├── 02-cluster/              # Local Kind HA configurations and deployment scripts
│   ├── kind-ha-config.yaml
│   └── setup-cluster.sh
├── 03-networking/           # Ingress & TLS configurations
│   ├── ingress-nginx.yaml
│   └── cert-manager-issuer.yaml
├── 04-security/             # RBAC scopes, NetworkPolicies, Vault secret configurations
│   ├── rbac-roles.yaml
│   ├── network-policies.yaml
│   └── secrets-vault.yaml
├── 05-monitoring/           # Alerting conditions and dashboard presets
│   ├── prometheus-rules.yaml
│   └── grafana-dashboard.json
├── 06-cicd/                 # GitOps definitions & GitHub Actions workflows
│   ├── argo-app.yaml
│   └── github-actions-workflow.yaml
├── 07-autoscaling/          # Workload (HPA/VPA) & Node autoscaling (Karpenter)
│   ├── hpa-vpa.yaml
│   └── karpenter-nodepool.yaml
├── 08-stateful-workloads/   # Stateful DB (CloudNativePG) & streaming clusters (Strimzi)
│   ├── postgres-ha.yaml
│   └── kafka-strimzi.yaml
├── 09-ai-data-services/     # FastAPI application and docker definitions
│   ├── fastapi-app/
│   │   ├── main.py
│   │   └── Dockerfile
│   └── k8s-deployment.yaml
├── 10-observability/        # Distributed tracing & aggregated log structures
│   ├── otel-collector-config.yaml
│   └── loki-promtail.yaml
├── 11-testing/              # Automated performance tests & chaos profiles
│   ├── k6-load-test.js
│   └── chaos-scenarios.yaml
├── 12-operations/           # DR runbooks & backup structures
│   ├── velero-backup.yaml
│   └── dr-failover-runbook.md
├── 13-troubleshooting/      # Failure mitigation playbooks & scripts
│   ├── scenarios.md
│   └── diagnose-platform.sh
├── 14-docs/                 # Educational cheat sheets & maps
│   ├── cheat-sheet.md
│   └── concept-map.md
├── 15-deliverables/         # Submission verification files
│   ├── submission-checklist.md
│   └── validate-deployment.sh
│
├── README.md                # This manual
├── PROJECT_GUIDE.md         # Hands-on labs manual
├── FINAL_CHECKLIST.md       # Final validation checklist
└── simulator.html           # Interactive Platform Simulator
```

---

## 🎯 Getting Started

To begin working through this capstone project:
1. Open and review [PROJECT_GUIDE.md](PROJECT_GUIDE.md) to read the 12 hands-on lab exercises.
2. Run `02-cluster/setup-cluster.sh` to spin up your local high-availability Kind cluster.
3. Open [simulator.html](simulator.html) directly in your browser to interactively understand how the systems respond to traffic spikes, configurations, failovers, and runtime failures.
