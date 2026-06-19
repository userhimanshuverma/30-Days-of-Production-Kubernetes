# 📖 Day 29 - Cost Optimization & Performance Engineering

### 🏷️ PHASE 5 - REAL PRODUCTION SYSTEMS

Welcome to Day 29 of **30 Days of Production Kubernetes**. Today, we bridge the gap between infrastructure efficiency and financial accountability. In modern cloud native operations, engineers must build platforms that are both highly performant and financially optimized.

---

## 🎯 Learning Objectives
By the end of today's deep-dive, you will be able to:
1. Explain **why Kubernetes costs grow unexpectedly** and how to halt cloud billing growth.
2. Formulate **optimal requests and limits** for CPU and Memory based on empirical metrics.
3. Architect robust, failure-resistant **Spot Instance failover strategies** using Karpenter.
4. Establish **node bin-packing and consolidation automation** to eliminate idle compute overhead.
5. Identify and resolve **Linux kernel scheduling performance bottlenecks** (CFS throttling, OOMKills).
6. Implement **Kubecost/OpenCost-based FinOps operating models** for precise cost chargebacks.

---

## 1. Why Kubernetes Costs Explode

In virtualized machine architectures, pricing is linear: 1 VM = 1 Cost Tag. In Kubernetes, the shared multi-tenant pool model makes cost mapping invisible. Without direct guardrails, application growth spirals into immense cloud waste.

### The Cost Escalation Pipeline
```mermaid
graph TD
    A[Application Traffic Growth] --> B[Devs spin up more Pod Replicas]
    B --> C[Nodes run out of CPU/Memory capacity]
    C --> D[Autoscaler boots up new On-Demand Nodes]
    D --> E[Vast Slack Waste: Pod Requests set 10x higher than usage]
    E --> F[High Cloud Compute & Storage Bills]
    F --> G[Finance flags budget anomalies & SRE gets pager warnings]
    style E fill:#f8cecc,stroke:#b85450,stroke-width:2px
    style F fill:#f8cecc,stroke:#b85450,stroke-width:2px
```

### The Kubernetes Cost Flow Model
```mermaid
graph TD
    A[Workload Code Commit] --> B[Pod Spec defined with Requests/Limits]
    B --> C{Scheduler assigns Pods to Nodes}
    C -->|Fits on existing node| D[Increase Node Utilization]
    C -->|No node has capacity| E[Pending Pod state]
    E --> F[Cluster Autoscaler / Karpenter triggers]
    F --> G[Provision New Cloud Node]
    G --> H[Increased Compute Cost]
    D --> I[Better Bin-Packing/Higher Efficiency]
    H --> J[Cloud Invoice / Bill]
    I --> K[Lower Per-Pod Unit Cost]
    J --> L[FinOps Chargeback to Team]
    K --> L
    style H fill:#f9d5e5,stroke:#333,stroke-width:2px
    style I fill:#d4f0f0,stroke:#333,stroke-width:2px
    style L fill:#cbe3db,stroke:#333,stroke-width:2px
```

---

## 2. Right Sizing Deep Dive

Setting container resources is a delicate balancing act. Underprovisioning causes crashes (OOM) and lag (throttling); overprovisioning runs up massive bills.

### The Anatomy of Container Allocations
*   **CPU Requests**: The scheduler allocates this baseline to place pods on a node. CPU requests act as the OS CFS shares (`cpu.shares`).
*   **CPU Limits**: The maximum CPU time a container can consume within a CFS period (100ms). Exceeding this triggers **CFS throttling** (`cpu.cfs_quota_us`).
*   **Memory Requests**: The memory allocation reserved by the scheduler.
*   **Memory Limits**: The hard threshold enforced on the cgroup. Exceeding this triggers the **Linux Kernel Out-of-Memory (OOM) Killer (Exit Code 137)**.

```mermaid
graph TD
    subgraph Total Node Capacity [Total Physical Node Capacity]
        subgraph Reserved [Reserved by Kube/OS]
            KR[Kube-Reserved]
            SR[System-Reserved]
            ET[Eviction Threshold]
        end
        subgraph Allocatable [Allocatable for Pods]
            subgraph Pod1 [Pod 1: Optimized]
                R1[Requests: 1 Core]
                U1[Actual: 800m]
                L1[Limits: 1.2 Cores]
            end
            subgraph Pod2 [Pod 2: Overprovisioned]
                R2[Requests: 4 Cores]
                U2[Actual: 100m]
                L2[Limits: 4 Cores]
                W2[Slack Waste: 3.9 Cores]
            end
        end
    end
    style Reserved fill:#fcedc9,stroke:#333
    style Pod1 fill:#dcf3e8,stroke:#333
    style Pod2 fill:#fcdbdb,stroke:#333
    style W2 fill:#ff6961,stroke:#333,stroke-width:2px
```

### Sizing Formulas (14-Day Window)
$$\text{Optimal CPU Request} = \text{Percentile}_{95}(\text{CPU Usage}_{14\text{d}}) \times 1.25$$
$$\text{Optimal Memory Request} = \max(\text{Memory Usage}_{14\text{d}}) \times 1.30$$

### The Right Sizing Feedback Loop
```mermaid
graph LR
    A[Collect Metrics] -->|Prometheus / Metrics Server| B[Analyze actual vs requested]
    B -->|VPA Recommendations / Kubecost| C{Is Slack Waste > 20%?}
    C -->|No| D[Keep Configuration]
    C -->|Yes| E[Recommend Resize]
    E --> F{Apply Strategy?}
    F -->|Auto| G[VPA Auto-updates Pods]
    F -->|Manual/GitOps| H[Create PR to git repository]
    G --> I[Pod restarts with new size]
    H --> J[Engineer reviews and merges]
    J --> I
    I --> K[Verify Performance & Cost Savings]
    style C fill:#fff2cc,stroke:#d6b656
    style G fill:#dae8fc,stroke:#6c8ebf
    style H fill:#d5e8d4,stroke:#82b366
```

---

## 3. Spot Instances

Spot Instances allow you to run workloads on unused cloud capacity at **up to a 90% discount**. SREs must design workloads to tolerate abrupt reclaims (2-minute warning on AWS, 30-second warning on GCP/Azure).

### Spot Scheduling Architecture
```mermaid
graph TD
    A[Workload allows Spot] --> B[Karpenter schedules on Spot Node]
    B --> C[Workload running at 70-90% discount]
    C --> D{Cloud Provider needs capacity}
    D -->|Capacity Reclaim| E[Spot Interruption Warning - 2 mins]
    E --> F[Spot Interruption Handler detects event]
    F --> G[Cordon & Drain Node]
    G --> H[SIGTERM sent to Pods]
    H -->|Graceful exit / 30s-60s| I[Worker finishes task & shuts down]
    G --> J[Reschedule remaining pods on other Nodes]
    J --> K[Karpenter spins up new On-Demand or Spot Node if needed]
    style E fill:#f8cecc,stroke:#b85450,stroke-width:2px
    style I fill:#d5e8d4,stroke:#82b366
    style K fill:#dae8fc,stroke:#6c8ebf
```

### Spot Workload Suitability Matrix
| Workload | Best Candidate? | Why? |
|---|---|---|
| **Batch processing workers** | **YES** | Stateless, pull jobs from queue, retryable. |
| **API Gateways & Core APIs** | **YES (Hybrid)** | Stateless. Run a blended pool of Spot and On-Demand nodes. |
| **CI/CD Build Runners** | **YES** | Interrupted jobs can be retried. |
| **SQL Databases & Message Queues** | **NO** | Stateful. Sudden shutdowns risk disk corruption and data loss. |

---

## 4. Resource Efficiency & Bin Packing

Resource fragmentation occurs when workloads are scattered sparsely across nodes, leaving enough aggregate free CPU/RAM to schedule pods, but split across nodes in quantities too small to schedule single pods.

### Fragmented vs Consolidated Node Bin-Packing
```mermaid
graph TD
    subgraph Bad: Fragmented Cluster [Fragmented Nodes: 3 Nodes @ 20% Utilization]
        N1[Node 1: CPU Reserved 80%, Actual 10%]
        N2[Node 2: CPU Reserved 70%, Actual 15%]
        N3[Node 3: CPU Reserved 60%, Actual 20%]
    end
    subgraph Good: Bin-Packed Cluster [Optimized Cluster: 1 Node @ 70% Utilization]
        N_opt[Node 1: Pods Consolidated, 2 Nodes Decommissioned]
    end
    style N1 fill:#f8cecc,stroke:#b85450
    style N2 fill:#f8cecc,stroke:#b85450
    style N3 fill:#f8cecc,stroke:#b85450
    style N_opt fill:#d5e8d4,stroke:#82b366,stroke-width:2px
```

### The Resource Efficiency Framework
```mermaid
graph TD
    A[Kubernetes Efficiency Framework] --> B[Request & Limit Tuning]
    A --> C[Spot Instance Strategy]
    A --> D[Node Consolidation]
    A --> E[Modern CPU Architectures]
    
    B --> B1[Right-size CPU/Mem with VPA]
    B --> B2[Align Limits to prevent throttling]
    
    C --> C1[Stateless / Batch Workloads]
    C --> C2[Spot interruption handlers]
    
    D --> D1[Bin packing via Karpenter]
    D --> D2[Scale down to zero off-hours]
    
    E --> E1[ARM64/Graviton adoption]
    E --> E2[AMD64 EPYC instance classes]
    
    style B fill:#dae8fc,stroke:#6c8ebf
    style C fill:#d5e8d4,stroke:#82b366
    style D fill:#ffe6cc,stroke:#d79b00
    style E fill:#e1d5e7,stroke:#9673a6
```

---

## 5. Performance Engineering & Bottlenecks

Cost optimization must never come at the cost of performance. Systems performance engineering requires monitoring low-level kernel metrics to identify when throttling compromises SLAs.

### Performance Bottleneck Analysis
```mermaid
graph TD
    A[Performance Degradation] --> B{CPU or Memory?}
    B -->|CPU Limit Too Low| C[CPU Throttling]
    B -->|CPU Request Too Low| D[No CPU Shares / Slow Threading]
    B -->|Memory Limit Too Low| E[OOMKill - Exit Code 137]
    B -->|Memory Request Too Low| F[Node Pressure / Eviction]
    C --> G[Increased API Latency]
    D --> G
    E --> H[Service Downtime / Pod Restarts]
    F --> I[Pod Status: Failed / Evicted]
    style C fill:#ffe599,stroke:#d6b656
    style E fill:#f8cecc,stroke:#b85450,stroke-width:2px
    style F fill:#f8cecc,stroke:#b85450
    style I fill:#f8cecc,stroke:#b85450
    style H fill:#f8cecc,stroke:#b85450
    style G fill:#f8cecc,stroke:#b85450
```

---

## 6. Autoscaling Coordination & Architecture

Proper resource efficiency relies on multi-tier autoscaling. The workload scales replicas horizontally (HPA), while the platform provisions and retires nodes (Karpenter).

### Autoscaling Feedback Architecture
```mermaid
graph TD
    subgraph Traffic Loop
        A[External Users / Clients] -->|Traffic Spikes| B[Service Endpoint]
    end
    subgraph Horizontal Pod Autoscaler
        B -->|Metrics collected| C[Prometheus / Metrics Server]
        C -->|CPU/Memory/Custom Metric| D{HPA evaluation}
        D -->|Target exceeded| E[Increase replicas in Deployment]
        E --> F[Create new Pods]
    end
    subgraph Karpenter / Node Autoscaler
        F -->|Pods cannot schedule| G[Pods marked PENDING]
        G -->|Watches API Server| H[Karpenter Controller]
        H -->|Calculates exact required shape| I[Call Cloud API to launch Nodes]
        I --> J[Nodes join cluster]
        J --> K[Pods scheduled and run]
    end
    style F fill:#ffe6cc,stroke:#d79b00
    style G fill:#ffcccc,stroke:#cc0000,stroke-width:2px
    style K fill:#d5e8d4,stroke:#82b366,stroke-width:2px
```

---

## 7. FinOps for Kubernetes

FinOps is an operational framework that establishes cost visibility and accountability.

### The FinOps Operating Model
```mermaid
graph LR
    subgraph Engineering [Platform & App Teams]
        ENG[Builds, scales, and operates workloads]
    end
    subgraph Finance [Finance & Procurement]
        FIN[Budgets, tracks, and purchases commitments]
    end
    subgraph Product [Product & Business Owners]
        PROD[Defines features, customer SLA, unit cost goals]
    end
    ENG <-->|Cost metrics vs App Performance| FIN
    FIN <-->|Budget alignment vs Margins| PROD
    PROD <-->|Feature costs vs Revenue| ENG
    style Engineering fill:#d5e8d4,stroke:#82b366
    style Finance fill:#f8cecc,stroke:#b85450
    style Product fill:#dae8fc,stroke:#6c8ebf
```

### The Cost Optimization Lifecycle
```mermaid
graph TD
    subgraph Inform Phase [1. Inform: Cost Visibility]
        A[Cost Allocation / Tagging] --> B[Kubecost Dashboards]
        B --> C[Showback & Chargeback Reports]
    end
    subgraph Optimize Phase [2. Optimize: Cost Savings]
        C --> D[Identify Waste & Slack]
        D --> E[Right-size Workloads]
        E --> F[Adopt Spot Instances & RIs]
    end
    subgraph Operate Phase [3. Operate: Continuous Tracking]
        F --> G[Autoscaling & Consolidation Policies]
        G --> H[Automated Governance & Budgets]
        H --> A
    end
    style Inform Phase fill:#dae8fc,stroke:#6c8ebf
    style Optimize Phase fill:#fff2cc,stroke:#d6b656
    style Operate Phase fill:#d5e8d4,stroke:#82b366
```

---

## 8. Real Production System Architecture Examples

To build high-performing, cost-efficient Kubernetes platforms, we apply targeted designs to specific workloads.

### A. SaaS Platform Architecture
*   **Design**: Namespace-per-tenant, Karpenter NodePool with isolation labels.
*   **Optimization**: Run development/tenant test spaces on Spot pools. Enforce off-hours scale-down to 0 replicas.
*   **Cost Breakdown**: 60% Spot compute, 20% On-Demand database nodes, 20% storage and network transfer.

### B. AI & Machine Learning Workloads
*   **Design**: GPU-enabled workloads (using `nvidia.com/gpu` limit schedulers).
*   **Optimization**: Set up aggressive scale-down-to-zero when training queues (Kubeflow / Ray) are empty, as idle GPU instances are extremely expensive (e.g., A100/H100 instances).
*   **Cost Breakdown**: 85% GPU instances, 10% high-throughput storage, 5% CPU/network nodes.

### C. Big Data Platforms
*   **Design**: Spark/Flink batch workers running on Spot nodes.
*   **Optimization**: Ensure Spark driver runs on On-Demand nodes, while executor pods run exclusively on Spot instances. Set high `terminationGracePeriodSeconds` and save checkpoints.
*   **Cost Breakdown**: 75% Spot executor nodes, 15% On-Demand driver/control nodes, 10% storage.

### Production Optimization Loop
```mermaid
graph TD
    subgraph Workload Namespace
        APP[Microservice Pods] -->|Logs & Traces| O1[Opentelemetry Collector]
        APP -->|CPU/Memory metrics| O2[Kubelet Summary API]
    end
    subgraph Control Loop
        PROM[Prometheus / Mimir] -->|Scrapes| O2
        PROM -->|Scrapes| O1
        VPA[VPA in Recommendation Mode] -->|Analyzes Prometheus data| PROM
        KEDA[KEDA Event-driven Autoscaler] -->|Scales replicas based on Queue/HTTP| APP
        KARP[Karpenter Node Autoscaler] -->|Watches pending pods & consolidates nodes| APP
    end
    subgraph GitOps Pipeline
        VPA -->|Recommends changes| PR[PR Creator Bot]
        PR -->|Auto-proposes new specs| GIT[GitHub Repository]
        GIT -->|ArgoCD / Flux syncs| APP
    end
    style Control Loop fill:#fcfcfc,stroke:#ccc
    style GitOps Pipeline fill:#f5fdf5,stroke:#82b366
```

### End-to-End Cost Management Workflow
```mermaid
graph LR
    A[Code Push] --> B[CI/CD dry run checks]
    B -->|Check resource request size| C{Is Request within limits?}
    C -->|No| D[Reject Build / Alert SRE]
    C -->|Yes| E[Deploy to Staging]
    E --> F[Performance Benchmarking / Load Test]
    F --> G[Extract actual cost metrics / Kubecost]
    G --> H[Deploy to Production]
    H --> I[Continuous Prometheus & Kubecost scraping]
    I --> J[FinOps Dashboard updates]
    I -->|Budget anomaly detected| K[Alert Slack / PagerDuty]
    style C fill:#fff2cc,stroke:#d6b656
    style K fill:#f8cecc,stroke:#b85450
    style J fill:#d5e8d4,stroke:#82b366
```

---

## 🛠️ Hands-On Labs Walkthrough
The following labs will guide you step-by-step through optimizing your cluster:

1.  **[Lab 1: Analyze Resource Waste](labs/lab-1-analyze-resource-waste.md)**: Identify resource slack and quantify waste.
2.  **[Lab 2: Right-Size Workloads](labs/lab-2-right-size-workloads.md)**: Configure VPA to size container allocations.
3.  **[Lab 3: Configure Spot Instances](labs/lab-3-configure-spot-instances.md)**: Deploy Spot-tolerating workloads.
4.  **[Lab 4: Optimize Node Utilization](labs/lab-4-optimize-node-utilization.md)**: Set up Karpenter Consolidation.
5.  **[Lab 5: Benchmark Pod Performance](labs/lab-5-benchmark-application-performance.md)**: Detect CPU CFS throttling under load.
6.  **[Lab 6: Tune Autoscaler Behavior](labs/lab-6-tune-autoscaling.md)**: Prevent scaling thrashing.
7.  **[Lab 7: Reduce Cluster Cost](labs/lab-7-reduce-cluster-costs.md)**: Clean up orphaned PVs and implement off-hours scaling.
8.  **[Lab 8: Improve Workload Efficiency](labs/lab-8-improve-workload-efficiency.md)**: Transition workloads to ARM64/Graviton.
9.  **[Lab 9: Build FinOps Dashboards](labs/lab-9-build-finops-dashboards.md)**: Design cost-tracking panels in Grafana.
10. **[Lab 10: Conduct Optimization Reviews](labs/lab-10-conduct-optimization-reviews.md)**: Establish risk-based platform audits.

---

## 🚨 Troubleshooting and Diagnosis Playbook
See the full details in our **[Troubleshooting Playbook](troubleshooting/troubleshooting-runbook.md)**.

| Error / Symptom | Root Cause | Resolution |
|---|---|---|
| **CPU Throttling** | Limit set below micro-burst needs | Remove limit or scale it to 1.5x - 3x of request |
| **Exit Code 137 (OOMKilled)** | Container exceeded memory limits | Increase cgroup memory limits |
| **Pods Stuck in Pending** | Autoscaler delays or capacity shortage | Configure low-priority pre-warmed pause pods |

---

## 🏆 Daily Challenge
Complete the **[Day 29 Challenge](exercises/exercise-challenge.md)**: take a bloated, $3,400/mo checkout microservice and refactor it into an optimized, Spot-friendly, autoscaling-optimized deployment manifest.
