# Production Observability Architecture

This diagram shows how logging fits into the three pillars of observability (Metrics, Traces, and Logs) and how they correlate using trace IDs and metadata.

```mermaid
flowchart TD
    subgraph Client ["Client / Request"]
        Req[User Request]
    end

    subgraph Pod ["App Workload Pod"]
        App[Container Code]
    end

    subgraph ObservabilityPipelines ["Observability Collectors"]
        PromAgent[Prometheus Agent]
        OTelCollector[OTel Collector]
        FBAgent[Fluent Bit DaemonSet]
    end

    subgraph StorageBackends ["Observability Storage"]
        MDB[(Metrics: Prometheus/Mimir)]
        TDB[(Traces: Tempo/Jaeger)]
        LDB[(Logs: Loki/Elasticsearch)]
    end

    subgraph UnifiedDashboard ["Unified SRE Dashboard"]
        Grafana[Grafana / Kibana UI]
    end

    %% Flow lines
    Req -->|Generates Trace Header| App
    App -->|Exposes /metrics endpoint| PromAgent
    App -->|Exports traces via gRPC| OTelCollector
    App -->|Writes JSON logs to stdout| FBAgent

    PromAgent --> MDB
    OTelCollector --> TDB
    FBAgent --> LDB

    MDB --> Grafana
    TDB --> Grafana
    LDB --> Grafana
    
    %% Correlative links
    Grafana -.->|1. Inspect Metric Alert| MDB
    Grafana -.->|2. Jump to Trace ID| TDB
    Grafana -.->|3. Correlate Trace ID to Logs| LDB
```

### The Correlation Loop:
1. **Metrics Alert:** A Prometheus alert fires because the `payment-service` request latency exceeds 2 seconds.
2. **Trace Inspection:** The SRE clicks the alert and opens Grafana Tempo to inspect the specific request trace, identifying that the payment service is blocked by a database query.
3. **Log Examination:** The dashboard uses the `TraceID` to query Loki, instantly showing only the log lines associated with that exact database query execution.
