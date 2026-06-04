# 📐 Production Autoscaling Architecture

This diagram shows a production-grade, multi-tier autoscaling architecture featuring Prometheus, KEDA, and Karpenter.

```mermaid
graph TD
    subgraph Clients ["Traffic Ingestion"]
        Traffic([Client Requests]) --> Ingress[Ingress Controller]
    end

    subgraph WorkloadScaling ["Workload Scaling Tier"]
        Ingress -->|Routes to| Pods["Application Pods"]
        Prometheus["Prometheus Server"] -->|Scrapes| Pods
        KEDA["KEDA (Kubernetes Event-driven Autoscaling)"] -->|Queries| Prometheus
        KEDA -->|Scales HPA resource| HPA["Horizontal Pod Autoscaler"]
        HPA -->|Adjusts Replicas| Deployment["App Deployment"]
        Deployment -->|Spawns Pods| Pods
    end

    subgraph InfraScaling ["Infrastructure Scaling Tier"]
        Scheduler["Kube-Scheduler"] -->|Pending Pods| Karpenter["Karpenter Controller"]
        Karpenter -->|Provisions Cloud Instances| CloudInstance["Cloud VMs (Spot / On-Demand)"]
        CloudInstance -->|Registers with| Scheduler
    end

    Deployment -.->|Unscheduled Pods| Scheduler

    style Clients fill:#EAECEE,stroke:#333
    style WorkloadScaling fill:#E8F8F5,stroke:#117A65,stroke-width:2px
    style InfraScaling fill:#FEF9E7,stroke:#D35400,stroke-width:2px
    style KEDA fill:#1ABC9C,stroke:#117A65,color:#fff
    style Karpenter fill:#E67E22,stroke:#A04000,color:#fff
    style Prometheus fill:#EC7063,stroke:#943126,color:#fff
```

### Explanatory Summary
* **KEDA for Custom Scaling:** KEDA (Kubernetes Event-driven Autoscaling) handles external and custom metric integrations (like Prometheus query evaluations or queue lengths) and manages HPA definitions behind the scenes.
* **Karpenter for Fast Node Provisioning:** Instead of AWS ASG-based Cluster Autoscaler, this architecture uses Karpenter. Karpenter bypasses node group controllers, directly creating virtual machines tailored to the unscheduled pods' resource configurations, speeding up node launch times from 3-5 minutes to under 60 seconds.
