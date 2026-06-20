# Scaling OpenTelemetry (OTel) Collector Pipelines in Production

This guide details best practices for scaling the OpenTelemetry Collector architecture and implementing cost-effective trace sampling.

---

## 🏛️ Deployment Architecture: Agent vs. Gateway

In production, run the OpenTelemetry Collector in a two-tier model:

```
[ Application Pods ] ──> [ OTel Collector DaemonSet ] ──> [ OTel Gateway Deployment ] ──> [ Storage Backend ]
   (Local SDK OTLP)          (Node agent / memory buffer)       (Tail-based sampling / retry)      (Tempo / Jaeger)
```

1.  **OTel DaemonSet (Agent)**: Runs on every node. Captures telemetry from local pods, adds Kubernetes node context (pod UID, host name), and forwards the data to the central Gateway.
2.  **OTel Gateway (Deployment)**: A stateless, horizontally scalable pool of collector instances behind a load balancer. It processes, batches, samples, and exports traces to storage backends (Tempo/Jaeger).

---

## ⚙️ Tail-Based Sampling (Reducing Trace Storage Costs)
Distributed tracing can generate massive volumes of data. To control costs, implement **Tail-Based Sampling** in the central Gateway. This allows you to evaluate traces *after* they are complete and drop successful requests while keeping errors and high-latency spans.

### Example: Tail-Sampling Configuration
```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 10000
    expected_new_traces_per_sec: 2000
    policies:
      # Policy 1: Always retain errors
      - name: errors-policy
        type: status_code
        status_code: {status_codes: [ERROR]}
      # Policy 2: Sample successful requests at 5% rate
      - name: success-rate-limiting
        type: probabilistic
        probabilistic: {sampling_percentage: 5.0}
      # Policy 3: Keep any requests with latency > 500ms
      - name: high-latency-policy
        type: latency
        latency: {threshold_ms: 500}
```

Apply this processor in your OTel pipeline service block:
```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, tail_sampling, batch]
      exporters: [otlp/tempo]
```
