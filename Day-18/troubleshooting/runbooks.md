# 🚨 Observability Playbook: Distributed Tracing Troubleshooting

This runbook helps platform engineers and SREs diagnose and resolve issues in the distributed tracing pipeline (SDKs, OpenTelemetry Collectors, Jaeger, and Context Propagation).

---

## Scenario 1: The Jaeger UI is Empty (No Traces Recorded)

### Symptoms
Applications are running, generating traffic, but selecting any service in the Jaeger UI dropdown yields no results, or the service dropdown itself is missing services.

### Root Cause Flowchart
```
[Verify Traffic] ──► [Check SDK Endpoint] ──► [Check Collector Logs] ──► [Check Collector Storage Exporter]
```

### Investigation & Diagnostics
1.  **Check Application SDK configuration**:
    *   Verify the container has the environment variable `OTEL_EXPORTER_OTLP_ENDPOINT` pointing to the collector.
    *   Ensure the protocol matches: `http/protobuf` or `http/json` usually targets port `4318`, whereas `gRPC` targets `4317`. If an SDK attempts to send gRPC data to port `4318`, connection aborts occur.
2.  **Verify network paths from the application Pod to the Collector service**:
    *   Run a curl check from inside the application container (if shell is available):
        ```bash
        kubectl exec -it <app-pod-name> -- curl -v http://otel-collector.observability.svc:4318/v1/traces
        ```
        If you get a connection timeout or DNS resolution failure, verify that CoreDNS is healthy and the service name matches.
3.  **Inspect OpenTelemetry Collector logs**:
    ```bash
    kubectl logs -n observability deployment/otel-collector -c otel-collector --tail=100
    ```
    *   If the collector is receiving spans but fails to output them, look for:
        ```text
        Exporting failed. Will retry. {"error": "connection refused"}
        ```
        This indicates the collector cannot connect to the Jaeger Collector (`jaeger-collector.observability:4317`). Check if the Jaeger pod is in a `CrashLoopBackOff`.
4.  **Confirm Sampling Rate**:
    *   If the SDK environment variable `OTEL_TRACES_SAMPLER` is configured to `always_off` or a fraction like `0.0001`, traces are actively dropped at source.

### Resolution
*   Adjust `OTEL_EXPORTER_OTLP_ENDPOINT` to the correct internal URI.
*   Confirm the protocol: Python and NodeJS SDKs default to `http/protobuf` (port `4318`), whereas Go defaults to `gRPC` (port `4317`). Ensure these align with the active OTel Collector ports.

---

## Scenario 2: Fragmented Trace Trees (Broken Context Propagation)

### Symptoms
In the Jaeger UI, instead of a single continuous trace representing the user's checkout journey, you see multiple separate, disconnected traces:
*   Trace A: `GET /checkout` (only containing the Gateway span)
*   Trace B: `POST /orders/create` (only containing backend order processor spans)
*   Trace C: `POST /payments/charge` (only containing payment gateway spans)

```
Fragmented Spans (Broken Propagation):
Trace 1: [Span A (Gateway)]
Trace 2:                  [Span B (Order Processor)]
Trace 3:                                           [Span C (Payment)]

Desired (Healthy Propagation):
Trace 1: [Span A (Gateway)]
            ├── [Span B (Order Processor)]
            │      └── [Span C (Payment)]
```

### Root Cause
Downstream services fail to extract the parent tracing headers from incoming network requests, or upstream services fail to inject them. This splits the execution graph into independent root traces.

### Investigation & Diagnostics
1.  **Inspect Incoming Headers**:
    *   Configure a downstream test container or log incoming request headers. Ensure `traceparent` exists in the incoming headers:
        ```text
        traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
        ```
2.  **Verify SDK Propagators Config**:
    *   Ensure the application SDK specifies W3C Trace Context. In OpenTelemetry, this can be configured globally via environment variables:
        ```yaml
        env:
          - name: OTEL_PROPAGATORS
            value: "tracecontext,baggage"
        ```
    *   If one service uses B3 propagation (legacy Zipkin standard) and the downstream service expects W3C tracecontext, propagation fails.

### Resolution
*   Enforce the global environment variable `OTEL_PROPAGATORS=tracecontext,baggage` across all microservices deployments.
*   If using manual HTTP client wrappers, verify that the active Go HTTP client or Node.js Axios instance is explicitly injected with the current context before making outbound calls.

---

## Scenario 3: OTel Collector Pod in CrashLoopBackOff (OOMKilled)

### Symptoms
The OpenTelemetry Collector crashes repeatedly. Describing the pod reveals:
```text
State:          Waiting
  Reason:       CrashLoopBackOff
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

### Root Cause
During high traffic spikes, the collector buffers spans in memory before exporting. If the volume exceeds memory limits, or if Jaeger is slow to accept data (causing buffer queues to fill), the collector exhausts its memory quota.

### Investigation & Diagnostics
1.  **Inspect Collector Memory Configuration**:
    *   Open the collector deployment manifest. Compare the container limits (`resources.limits.memory`) to the `memory_limiter` processor parameters in the ConfigMap.
    *   If `resources.limits.memory` is set to `512Mi`, but the `memory_limiter` check is not configured or configured to activate at `1Gi`, the container will be terminated by the Kubernetes host kernel (OOMKilled) before the OTel limiter can drop data.
2.  **Verify Storage Backpressure**:
    *   Search the collector container log history before the crash:
        ```text
        Buffer queue full. Dropping spans.
        ```
        This indicates downstream storage (Elasticsearch/Jaeger) is slow, causing the collector's internal memory buffer queues to reach maximum limits.

### Resolution
Ensure the `memory_limiter` is active and aligned to the pod resource limits. The processor limit must be set below the Kubernetes limits:
```yaml
# ConfigMap Processor
processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80 # Will drop/apply backpressure at 80% of 512Mi (~409Mi)
# Deployment Resources
resources:
  limits:
    memory: "512Mi"
```

---

## Scenario 4: Collector Dropping Spans

### Symptoms
Traces in Jaeger are missing child spans, or some requests are not recorded at all. The OTel Collector metrics report `otelcol_processor_dropped_spans` increases.

### Root Cause
The Collector's queues are overflowing, or the `memory_limiter` processor is actively discarding incoming telemetry to prevent OOM crashes.

### Investigation & Diagnostics
1.  Check the Collector's metrics endpoint (default port `8888` at path `/metrics`) to check the drop counts:
    ```bash
    kubectl exec -it <collector-pod> -n observability -- curl http://localhost:8888/metrics | grep dropped
    ```
2.  Review log files for the following warning message:
    ```text
    Processor queue is full. Spans dropped.
    ```
    This indicates that exporters cannot write data fast enough to keep up with the ingress.

### Resolution
*   **Scale the Collectors**: Increase the replica count of the OTel Collector deployment.
*   **Optimize Batch Processor**: Increase `send_batch_size` and `timeout` parameters to bundle and write spans more efficiently.
*   **Scale Jaeger/Storage**: If Elasticsearch is CPU bottlenecked, add replicas or optimize the ES write index refresh rate.

---

## Scenario 5: Broken/Missing Database Call Spans

### Symptoms
Traces show HTTP routes and microservice communication, but database call spans (like `SELECT` or `UPDATE` statements) are completely missing.

### Root Cause
The database driver or client library is not wrapped by OpenTelemetry. Unlike HTTP, database calls cannot be automatically instrumented via proxying; the database driver/connection pool wrapper in the code must be explicitly instrumented.

### Investigation & Diagnostics
*   Inspect the application initialization code.
*   For Go, check if the SQL driver is registered using libraries like `otelsql` or `gorm-opentelemetry`.
*   For Java/Node, verify that automatic database instrumentation plugins are enabled.

### Resolution
Wrap database connection definitions in the codebase:
```go
// Go Gorm example
import "github.com/uptrace/opentelemetry-go-extra/otelsql"

db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
if err := db.Use(otelgorm.NewPlugin()); err != nil {
    panic(err)
}
```

*Proceed to [Day 18 Exercises: Tail-based sampling challenge](../exercises/assignment.md).*
