# 📐 Traffic Spike Handling

This diagram illustrates the mitigation steps and components involved in absorbing sudden, massive traffic surges.

```mermaid
graph TD
    Spike([Sudden 10x Traffic Spike]) --> Gateway[Ingress Gateway]
    
    subgraph Absorber ["Spike Absorbers"]
        Gateway -->|1. Rate Limit / Queue| Queue[Kafka / Queue Buffer]
        Gateway -->|2. Burst Capacity| WarmNodes["Over-provisioned 'Pause' Pods<br/>(Priority Preemption Target)"]
    end

    subgraph Scaler ["Reactive Scaling"]
        Queue -->|Trigger HPA scale| HPA[HPA Controller]
        HPA -->|Deploy new pods| Deploy[App Deployments]
        Deploy -->|Preempts| WarmNodes
        Deploy -->|Consumes Queue| Queue
    end

    style Absorber fill:#FDEDEC,stroke:#C0392B,stroke-width:2px
    style Scaler fill:#EAFAF1,stroke:#27AE60,stroke-width:2px
    style Queue fill:#EC7063,stroke:#922B21,color:#fff
    style WarmNodes fill:#F4D03F,stroke:#9A7D0A,color:#fff
    style HPA fill:#8E44AD,stroke:#5B2C6F,color:#fff
```

### Explanatory Summary
* **Queue Buffering:** For asynchronous processes, traffic surges are absorbed by queue systems (like Kafka or RabbitMQ) while the scale-up takes place. This avoids application resource exhaustion.
* **Warm Standby via Pause Pods:** SREs configure low-priority "Pause" pods (running a sleep loop) that reserve space on nodes. When high-priority application pods scale up, the scheduler evicts the low-priority pause pods instantly, giving the application immediate head-room without waiting for new VMs to boot.
