# 🖼️ Production Observability Visual Guide: 12 Tracing Diagrams

This folder contains high-resolution architecture diagrams mapped using Mermaid. These diagrams serve as visual templates for internal training or architecture design reviews.

---

## 1. Trace Lifecycle
*Visualizes the journey of trace data from application instrumentation to storage and query.*

```mermaid
graph TD
    User["User Trigger Action"] -->|1. Generate Request| App["Application Code (Instrumented)"]
    App -->|2. Create API Span| OTelSDK["OpenTelemetry SDK in App"]
    OTelSDK -->|3. Buffer & Batch Spans| Queue["In-Memory Span Queue"]
    Queue -->|4. Push (OTLP/gRPC)| OTelAgent["OTel Collector (DaemonSet Agent)"]
    OTelAgent -->|5. Forward (OTLP/gRPC)| OTelGW["OTel Collector (Deployment Gateway)"]
    OTelGW -->|6. Batch Write| DB["Storage Backend (Elasticsearch/Tempo)"]
    DB -->|7. Query Data| JaegerUI["Jaeger UI / Query API"]
    SRE["SRE / Developer"] -->|8. Search Traces| JaegerUI
```

---

## 2. OpenTelemetry Architecture
*The separation between APIs, SDKs, Collectors, and Backends.*

```mermaid
graph LR
    subgraph "Application Runtime Boundary"
        App["App Logic"] -->|Instruments| API["OTel API (No-Op Interface)"]
        API -->|Binds to| SDK["OTel SDK (Concrete Logic)"]
        SDK -->|Pushes Spans| BSP["BatchSpanProcessor"]
    end

    subgraph "Kubernetes Nodes"
        BSP -->|OTLP/gRPC| CollectorAgent["OTel Collector DaemonSet (Agent)"]
    end

    subgraph "Observability Control Plane"
        CollectorAgent -->|OTLP/gRPC| CollectorGW["OTel Collector Deployment (Gateway)"]
        CollectorGW -->|Format Protocol| Export["Exporter Layer"]
    end

    Export -->|Trace JSON| Jaeger["Jaeger"]
    Export -->|Metrics Data| Prom["Prometheus"]
    Export -->|Log Streams| Loki["Grafana Loki"]
```

---

## 3. Request Journey Across Services
*Flow of a user payment checkout request across multiple Kubernetes microservices.*

```mermaid
sequenceDiagram
    autonumber
    actor User as User Browser
    participant GW as API Gateway (Ingress)
    participant Auth as Auth Service
    participant Order as Order Processor
    participant Pay as Payment Gateway
    participant DB as Postgres Database

    User->>GW: POST /checkout (no headers)
    Note over GW: Creates ROOT Span<br>Generates TraceID: 9a8b...
    GW->>Auth: GET /validate-token
    Note over Auth: Extract Header &<br>Create Child Span
    Auth-->>GW: HTTP 200 OK (12ms)
    
    GW->>Order: POST /orders/create
    Note over Order: Extract Trace Context<br>Create Child Span
    
    Order->>DB: INSERT INTO orders...
    Note over DB: Database driver spans SQL query
    DB-->>Order: SQL Success (8ms)
    
    Order->>Pay: POST /payments/charge
    Note over Pay: Call External Stripe API<br>Child Span Created
    Pay-->>Order: Charged Successful (1200ms)
    
    Order-->>GW: HTTP 201 Created (1220ms)
    GW-->>User: Success (1240ms)
```

---

## 4. Span Hierarchy
*Gantt-chart view and Parent-Child Directed Acyclic Graph (DAG) relationship.*

```mermaid
graph TD
    Root["Span A: API Gateway Ingress (Parent)"]
    Root --> Child1["Span B: Authenticate Token (Child)"]
    Root --> Child2["Span C: Order Processing (Child)"]
    Child2 --> SubChild1["Span D: Check Stock DB (Grandchild)"]
    Child2 --> SubChild2["Span E: Charge Stripe API (Grandchild)"]
```

---

## 5. Context Propagation Flow
*Stitching downstream calls together using W3C HTTP header inject/extract loop.*

```mermaid
graph TD
    subgraph "Service A (Client)"
        CtxA["Active Context (TraceID: abc, SpanID: 111)"]
        Inject["OTel Propagator: Inject Ctx"]
        HTTPOut["Outgoing HTTP Request"]
        
        CtxA --> Inject
        Inject -->|Serializes Ctx to HTTP Headers| HTTPOut
    end

    HTTPOut -->|Network Transit: 'traceparent: 00-abc-111-01'| HTTPIn

    subgraph "Service B (Server)"
        HTTPIn["Incoming HTTP Request"]
        Extract["OTel Propagator: Extract Ctx"]
        CtxB["New Child Span Context (TraceID: abc, SpanID: 222, ParentID: 111)"]
        
        HTTPIn --> Extract
        Extract -->|Deserializes HTTP Headers| CtxB
    end
```

---

## 6. Jaeger Architecture
*High-scale Jaeger components setup inside a Kubernetes cluster.*

```mermaid
graph TD
    App["App Tracing SDK"] -->|OTLP / UDP| Agent["Jaeger Agent (DaemonSet Pod)"]
    Agent -->|gRPC Batch| Collector["Jaeger Collector (Deployment)"]
    Collector -->|Write Query Indices| Storage["Elasticsearch / OpenSearch Cluster"]
    Storage <-->|Read Data| QueryAPI["Jaeger Query API (Service)"]
    QueryAPI <-->|Render Timelines| UI["Jaeger UI Interface"]
```

---

## 7. OpenTelemetry Collector Pipeline
*The internal telemetry processing stages inside an OTel Collector pod.*

```mermaid
graph LR
    subgraph "OTel Collector Pipeline"
        direction LR
        
        subgraph "1. Receivers"
            OTLP_gRPC["OTLP (gRPC)"]
            OTLP_HTTP["OTLP (HTTP)"]
            JaegerUDP["Jaeger (UDP)"]
        end

        subgraph "2. Processors"
            Memory["memory_limiter"]
            Batch["batch"]
            Filter["filter (drop healthz)"]
            Sampling["tail_sampling"]
            
            Memory --> Batch --> Filter --> Sampling
        end

        subgraph "3. Exporters"
            ExportJaeger["OTLP / Jaeger Exporter"]
            ExportProm["Prometheus Exporter"]
            ExportFile["Logging / File Exporter"]
        end
        
        OTLP_gRPC & OTLP_HTTP & JaegerUDP --> Memory
        Sampling --> ExportJaeger & ExportProm & ExportFile
    end
```

---

## 8. End-to-End Observability Architecture in Kubernetes
*Unified system showing Prometheus metrics, Loki logs, and Jaeger traces correlated.*

```mermaid
graph TD
    subgraph "Kubernetes Pod"
        AppPod["App Container"] -->|Prometheus Metrics| ScrapeEndpoint["/metrics"]
        AppPod -->|JSON Logs with TraceID| Stdout["Stdout logstream"]
        AppPod -->|Spans via SDK| OTelDS["OTel DaemonSet Agent"]
    end

    ScrapeEndpoint -->|Scraped by| Prom["Prometheus Operator"]
    Stdout -->|Collected by| FluentBit["FluentBit DaemonSet"]
    OTelDS -->|Traces| OTelGW["OTel Collector Gateway"]

    FluentBit -->|Ship Logs| Loki["Grafana Loki"]
    OTelGW -->|Ship Traces| Jaeger["Jaeger Storage"]

    GrafanaUI["Unified Grafana Dashboard"]
    GrafanaUI -->|Query Logs| Loki
    GrafanaUI -->|Query Metrics| Prom
    GrafanaUI -->|Query Traces| Jaeger
```

---

## 9. Performance Bottleneck Workflow
*Identifying serial database calls, fan-out loops, and external latencies.*

```mermaid
graph TD
    Look["Look at Trace Gantt Chart"] --> CheckStaircase{Is it a staircase?}
    
    CheckStaircase -->|Yes| SerialCall["Diagnose: Sequential Downstream Calls"]
    SerialCall --> FixSerial["Fix: Refactor calls to execute asynchronously/parallel"]
    
    CheckStaircase -->|No| CheckComb{Is it a comb pattern?}
    
    CheckComb -->|Yes| N1Query["Diagnose: N+1 Database Queries"]
    N1Query --> FixN1["Fix: Rewrite SQL to join or preload batches"]
    
    CheckComb -->|No| CheckGap{Is there a floating gap?}
    
    CheckGap -->|Yes| CPUStarve["Diagnose: CPU starvation or Locked DB connections"]
    CPUStarve --> FixCPU["Fix: Adjust resource limits or expand pool size"]
    
    CheckGap -->|No| ExternalDelay["Diagnose: Third-party API slow response"]
    ExternalDelay --> FixExt["Fix: Implement caching or fallback queues"]
```

---

## 10. Microservice Request Tracing Sequence
*Step-by-step trace generation in a transaction.*

```mermaid
sequenceDiagram
    autonumber
    participant App as Front-End Ingress
    participant Collector as OTel Collector
    participant Storage as Jaeger Indexer
    
    Note over App: App starts Root Span A
    App->>Collector: Send Span A Metadata (Start)
    Note over App: App calls downstream API (Span B)
    App->>Collector: Send Span B Metadata (Start)
    Note over App: Downstream returns success
    App->>Collector: Send Span B Metadata (End)
    Note over App: Root transaction completes
    App->>Collector: Send Span A Metadata (End)
    Note over Collector: OTel Collector batches spans
    Collector->>Storage: Bulk indexing write to Storage
```

---

## 11. Production Tracing Architecture
*A highly resilient tracing ingestion topology buffering data with Kafka to protect storage backend during spikes.*

```mermaid
graph LR
    subgraph "K8s Nodes"
        PodA["Pod A (OTel SDK)"] -->|OTLP/gRPC| CollectorA["OTel Collector Agent"]
        PodB["Pod B (OTel SDK)"] -->|OTLP/gRPC| CollectorB["OTel Collector Agent"]
    end

    subgraph "Ingest Buffer Layer"
        CollectorA & CollectorB -->|OTLP/Kafka| Kafka["Apache Kafka Cluster"]
    end

    subgraph "Processing Layer"
        Kafka -->|Consumer Groups| OTelGW["OTel Collector Gateway (Autoscaled)"]
    end

    subgraph "Storage Backend"
        OTelGW -->|Write Traces| OpenSearch["OpenSearch Index Cluster"]
    end
```

---

## 12. Incident Investigation Flow
*Using tracing to quickly isolate production errors.*

```mermaid
graph TD
    Alert["1. Alert Fired: Gateway HTTP 5xx Spike"]
    Alert --> LookLogs["2. Search Gateway logs for Trace ID"]
    LookLogs --> FindTrace["3. Look up Trace ID in Jaeger"]
    FindTrace --> InspectSpans{"4. Inspect Span Tree: Where does it red-flash?"}
    
    InspectSpans -->|Failed Database Span| CheckDB["5a. Diagnostic: Query locked or table schema error"]
    InspectSpans -->|Failed Payment Span| CheckStripe["5b. Diagnostic: External Stripe API timed out"]
    InspectSpans -->|Failed Core App Span| CheckAppLogs["5c. Diagnostic: Correlate Trace ID to Pod logs for Stack Trace"]
    
    CheckDB & CheckStripe & CheckAppLogs --> FixInc["6. Mitigate Incident & Resolve Outage"]
```

---

*Continue to the [manifests/](../manifests/) folder to view configurations that deploy this distributed tracing ecosystem in Kubernetes.*
