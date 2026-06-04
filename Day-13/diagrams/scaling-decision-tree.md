# 📐 Scaling Decision Tree

This decision tree helps platform engineers choose the correct autoscaling mechanism for different types of applications.

```mermaid
graph TD
    Start([Evaluate Workload for Scaling]) --> IsStateful{Is the workload stateful?}
    
    IsStateful -->|Yes| CanScaleHorizontally{Can application sync state<br/>across dynamic replicas?}
    IsStateful -->|No| ScaleMetricType{What resource spikes under load?}
    
    CanScaleHorizontally -->|Yes| ScaleMetricType
    CanScaleHorizontally -->|No| VPARecom[Use VPA in Off/Recommendation Mode<br/>or Manual Sizing]
    
    ScaleMetricType -->|CPU / Memory requests| IsHPAConflict{Is memory scaling stable<br/>without GC lag?}
    ScaleMetricType -->|External Queue / Kafka Lag| HPAQueue[Use HPA with Custom/External Metrics]
    ScaleMetricType -->|High Startup Cost / JVM heap| VPAMain[Use VPA in Auto Mode]

    IsHPAConflict -->|Yes| HPACpuMem[Use HPA on CPU / Memory]
    IsHPAConflict -->|No| VPAOnly[Use VPA for vertical sizing<br/>or HPA on Custom Metrics]
    
    style Start fill:#EAECEE,stroke:#333
    style IsStateful fill:#FADBD8,stroke:#C0392B
    style CanScaleHorizontally fill:#FDEDEC,stroke:#E74C3C
    style ScaleMetricType fill:#FCF3CF,stroke:#F1C40F
    style IsHPAConflict fill:#FDEDEC,stroke:#E74C3C
    style HPACpuMem fill:#D4EFDF,stroke:#27AE60,stroke-width:2px
    style HPAQueue fill:#D4EFDF,stroke:#27AE60,stroke-width:2px
    style VPAMain fill:#D1F2EB,stroke:#1ABC9C,stroke-width:2px
    style VPAOnly fill:#D1F2EB,stroke:#1ABC9C,stroke-width:2px
    style VPARecom fill:#E8DAEF,stroke:#8E44AD,stroke-width:2px
```

### Explanatory Summary
* **Stateful vs. Stateless:** Stateless applications are natural candidates for HPA (horizontal scaling). Stateful applications (like databases) require VPA or manual sizing unless they have native horizontal clustering support (e.g., Elasticsearch, Cassandra).
* **Lagging vs. Leading metrics:** For queue consumers (Kafka, RabbitMQ, SQS), scale on queue depth / lag using Custom/External metrics. CPU/Memory is usually a lagging indicator.
* **HPA vs. VPA Conflict:** Avoid running HPA and VPA together on the same metric (CPU/Memory). If memory is unstable due to runtime engine GC habits, prefer VPA (vertical resizing) or HPA scaled on custom application metrics (e.g. connections).
