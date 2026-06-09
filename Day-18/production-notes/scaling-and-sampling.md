# ⚡ SRE Production Guide: Scaling, Sampling, & Storage Costs

Operating distributed tracing at scale introduces significant infrastructure challenges. Unlike metrics (which grow with service instances, not traffic volume), **tracing data volume grows linearly with request rate**. 

If your gateway processes 50,000 requests per second (RPS), and each request touches 10 services (generating 20 spans), storing 100% of traces results in:

$$\text{50,000 requests/sec} \times \text{20 spans/request} = 1,000,000\text{ spans/sec}$$

At roughly 1.5 KB per serialized span, this is **1.5 GB/sec** or **129 TB of storage per day**. Operating this is cost-prohibitive. This guide covers how to scale, budget, and design production tracing pipelines.

---

## 📈 Sampling Strategies: Head-based vs. Tail-based

To control costs and collector resource consumption, you must use **Sampling**. There are two major paradigms:

```
┌────────────────────────────────────────────────────────────────────────┐
│                              Head-Based                                │
│                                                                        │
│  [User Request] ──► [API Gateway] ──► (Sampling Decision Made Here)    │
│                        │                                               │
│                        ├──► [Sampled = True]  ──► Trace is recorded    │
│                        └──► [Sampled = False] ──► Spans are dropped    │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│                              Tail-Based                                │
│                                                                        │
│  [User Request] ──► [API Gateway] ──► [Service A] ──► [Service B]       │
│                        │                  │              │             │
│                        ▼                  ▼              ▼             │
│                  All Spans Sent to OTel Collector Buffer in Memory    │
│                                           │                            │
│                  Is there an HTTP 5xx or latency > 1.5s?               │
│                        ├──► YES ──► Save entire Trace to Storage       │
│                        └──► NO  ──► Drop Trace from Memory Buffer      │
└────────────────────────────────────────────────────────────────────────┘
```

### 1. Head-Based Sampling (SDK Level)
*   **Mechanism**: The decision to keep or drop a trace is made at the **ingress (head) of the request** (typically by the API Gateway or root service SDK). 
*   **How it works**: A configuration like `RatioBased(0.01)` selects a randomized 1% of transactions. The gateway stamps `traceparent` with flags `01` (sampled) or `00` (dropped). Downstream services extract this flag and behave accordingly.
*   **Pros**: 
    *   Highly efficient. If a trace is not sampled, child services do not even allocate memory or emit span packets, saving bandwidth and network traffic.
*   **Cons**:
    *   **Blind to errors**: If a critical payment failure occurs, but the trace falls outside the randomized 1% sampling bucket, **that error is lost forever**.

### 2. Tail-Based Sampling (Collector Level)
*   **Mechanism**: The decision to keep or drop a trace is deferred until the **entire execution is complete (tail)**.
*   **How it works**: The OTel Collector receives 100% of spans from applications, buffers them in memory for a short period (e.g., 10 seconds) until all spans for a given `Trace ID` arrive, and then evaluates user-defined rules:
    *   *Rule A*: Keep all traces containing spans with status = `Error`.
    *   *Rule B*: Keep all traces with duration > 1,500ms.
    *   *Rule C*: Keep 0.1% of successful, normal HTTP 200 traces.
*   **Pros**:
    *   **Guarantees 100% visibility into anomalies and errors** while pruning normal data to minimize storage.
*   **Cons**:
    *   **High memory/resource overhead** on the OTel Collector, which must maintain a stateful in-memory buffer of all active traces.
    *   Requires a stateful routing layer (routing all spans of a specific `Trace ID` to the exact same Collector instance).

### 3. Adaptive Sampling (Dynamic Sampling)
*   **Mechanism**: Implemented by advanced platforms (like Jaeger or Honeycomb). The SDK polls the collector for dynamic sampling rates per endpoint. 
*   **How it works**: An endpoint with low traffic (`/checkout/pay`) is sampled at 100%, while a high-frequency polling endpoint (`/healthz`) is automatically throttled and sampled at 0.001%.

---

## 💾 Storage Backends and Sizing (Elasticsearch vs. Tempo vs. Jaeger Local)

Choosing and scaling the database where traces are persisted:

| Storage Backend | Architecture Type | Pros | Cons | Best For |
| :--- | :--- | :--- | :--- | :--- |
| **Elasticsearch / OpenSearch** | Indexed Document Store | - Full-text search on any attribute<br>- Fast lookup of complex queries | - Very high CPU/Memory overhead<br>- Requires massive disk space | Enterprise tracing with complex indexing |
| **Grafana Tempo / Jaeger native Object Storage** | Index-free Columnar / Object Storage (S3/GCS) | - Massive cost savings (S3 rates)<br>- Near infinite scale | - Slower trace searches (relies on log integration or minimal index) | SRE teams running log-to-trace correlation |
| **Jaeger In-Memory / Badger** | Key-Value Store / Local | - Zero config<br>- Extremely fast | - Ephemeral (data disappears on pod restart) | Local Kind/Minikube clusters, QA |

---

## 🚀 Performance Tuning the OTel Collector

When routing heavy tracing loads through the OpenTelemetry Collector, you must configure resource safeguards to prevent OOM (Out Of Memory) aborts.

### The `memory_limiter` Processor
This processor is **mandatory** for every production Collector deployment. It periodically monitors memory usage and drops data or applies backpressure when thresholds are breached.

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80         # Hard ceiling (OTel drops data when breached)
    spike_limit_percentage: 20   # Maximum expected memory spike between checks
```

### Batching configuration
Always batch your traces before exporting to reduce connection handshakes and payload overhead.
```yaml
processors:
  batch:
    send_batch_size: 8192
    timeout: 5s
    send_batch_max_size: 10240
```

---

## 🔗 Correlating Logs and Traces

Traces and logs are siloed data sources unless linked. In a production environment, you should configure your application framework loggers to inject `Trace ID` and `Span ID` into every single structured log output.

### JSON Structured Log Format:
```json
{
  "timestamp": "2026-06-09T20:14:02.112Z",
  "level": "error",
  "service": "payment-processor",
  "message": "Stripe card validation failed: 4022",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7"
}
```

### Why this is powerful:
In log visualizers like Grafana Loki or Kibana, you can click on an error log, click a dynamic link mapping `trace_id` to Jaeger, and open the exact execution graph of that request. Alternatively, in Jaeger, clicking on a span event will pull up only the logs written by that container during that specific span duration.

---

## ❄️ Instrumentation Overhead: The Myth vs. Reality

Skepticism about tracing overhead is common among application teams. Here is the operational breakdown:

1.  **CPU Overhead**: Writing spans is incredibly fast (usually < 200 nanoseconds). The heavy performance cost is not the API call, but rather the SDK serializing the span data and pushing it over gRPC. By using the `BatchSpanProcessor` (which exports spans asynchronously in a background worker thread), application request latency is unaffected.
2.  **Memory Overhead**: If downstream backpressure occurs (e.g., OTel Collector is down), the SDK's internal ring buffer will fill up. It is critical to enforce a maximum queue capacity (`max_queue_size`) in your SDK initialization. If the queue overflows, **the SDK must drop new spans rather than allocate more memory and crash the application**.

*Next: Review the manifests/ folder to see concrete configurations for deploying these components in Kubernetes.*
