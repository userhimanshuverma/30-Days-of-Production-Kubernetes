# 📐 Vertical Pod Autoscaler (VPA) Workflow

This diagram shows how VPA monitors workloads, generates resource recommendations, and executes auto-adjustments.

```mermaid
graph TD
    subgraph VPASystem ["VPA Controllers"]
        Recommender["VPA Recommender<br/>(Calculates targets)"]
        Updater["VPA Updater<br/>(Decides evictions)"]
        Webhook["VPA Admission Webhook<br/>(Mutating Webhook)"]
    end

    MetricsServer["Metrics Server / Prometheus"]
    Pod["Running Pod<br/>(Target Workload)"]
    APIServer["K8s API Server"]
    Deployment["Workload Deployment"]

    %% Flow lines
    Pod -->|CPU / Mem Usage| MetricsServer
    MetricsServer -->|Scraped by| Recommender
    Recommender -->|Writes recommendations| APIServer
    Updater -->|Reads recommendations| APIServer
    Updater -->|Evaluates Target vs Actual| Updater
    Updater -->|Evicts out-of-spec Pod| Pod
    Deployment -->|Recreates Pod| APIServer
    APIServer -->|Intercepts creation| Webhook
    Webhook -->|Injects recommendations<br/>into Pod spec| APIServer
    APIServer -->|Schedules optimized Pod| Pod

    style VPASystem fill:#F5EEF8,stroke:#6C3483,stroke-width:2px
    style Recommender fill:#A569BD,stroke:#5B2C6F,color:#fff
    style Updater fill:#EC7063,stroke:#78281F,color:#fff
    style Webhook fill:#5DADE2,stroke:#1F618D,color:#fff
    style Pod fill:#52BE80,stroke:#196F3D,color:#fff
```

### Explanatory Summary
1. **Usage Monitoring:** The **Recommender** pulls historical and current CPU/Memory usage metrics from the Metrics Server or Prometheus.
2. **Recommendation Generation:** The Recommender continually updates the VPA resource object's `status.recommendation` block with target requests and limits (Lower Bound, Target, Upper Bound, Uncapped Target).
3. **Eviction Loop:** In `Auto` mode, the **Updater** watches running pods. If a pod's current CPU/memory settings deviate significantly from the recommended target, the Updater evicts the pod.
4. **Mutating Webhook Injection:** When the Deployment controller recreates the evicted pod, the creation request is intercepted by the **VPA Mutating Admission Webhook**. The webhook replaces the developer-configured requests/limits with the VPA's latest target recommendations before scheduling the pod to a node.
