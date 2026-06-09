# 🏆 Daily Assignment: Tail-based Sampling and Filtering

Welcome SRE! Your production Kubernetes environment is experiencing high tracing storage costs due to a massive volume of successful HTTP requests and automated health probes polluting the index.

Your task is to modify the OpenTelemetry Collector gateway configuration to optimize span processing.

---

## 🎯 Scenario Requirements

1.  **Drop noisy health checks**: Discard all spans targeting `/healthz` or `/metrics` endpoints.
2.  **Implement Tail-based Sampling**:
    *   Save **100% of traces** that contain any span with an **Error** status.
    *   Save **100% of traces** that take longer than **1,000ms (1 second)** to execute.
    *   Sample only **5% of normal, successful traces** (probabilistic sampling).

---

## 🛠️ Step-by-Step Instructions

### Step 1: Open the Collector Configuration
Locate and edit your `manifests/otel-collector.yaml` file. You will need to modify the ConfigMap: `otel-collector-config`.

### Step 2: Implement the `tail_sampling` Processor
Add a new processor named `tail_sampling` under `processors:` in the ConfigMap. 

```yaml
processors:
  tail_sampling:
    decision_wait: 10s       # Wait time for spans of a trace ID to arrive
    num_traces: 10000        # Size of trace ID cache
    expected_new_traces_per_sec: 2000
    policies:
      # Policy 1: Always sample traces that contain error spans
      - name: error-spans
        type: status_code
        status_code: {status_codes: [ERROR]}

      # Policy 2: Always sample slow traces (duration > 1000ms)
      - name: slow-traces
        type: latency
        latency: {threshold_ms: 1000}

      # Policy 3: Sample 5% of all other (successful) traces
      - name: successful-traces-ratio
        type: probabilistic
        probabilistic: {sampling_percentage: 5.0}
```

### Step 3: Update the Traces Pipeline
You must register the new `tail_sampling` processor in the active traces pipeline. Modify `service.pipelines.traces`:

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, filter/healthz, tail_sampling, batch]
      exporters: [otlp/jaeger, logging]
```

> **IMPORTANT ARCHITECTURAL NOTE:** The order of processors in a pipeline matters!
> 1. `memory_limiter` should run first to drop incoming spans immediately if memory is low.
> 2. `filter/healthz` should run next to drop health probes before they register in the stateful tail sampler (saving memory).
> 3. `tail_sampling` aggregates the trace state.
> 4. `batch` compresses the sampled output spans before network transport.

---

## 🔬 Validation Check

Apply the modified configuration to your Kubernetes cluster:

```bash
kubectl apply -f manifests/otel-collector.yaml
```

Restart the collector deployment to pick up the changes:

```bash
kubectl rollout restart deployment/otel-collector -n observability
```

Verify that the collector starts up and validates the new configuration:

```bash
kubectl get pods -n observability
kubectl logs -n observability -l app=otel-collector -c otel-collector --tail=50
```

Confirm that the OTel log displays the pipelines starting with the new `tail_sampling` processor:
```text
info    service/pipelines.go:120   Traces pipeline started with tail_sampling processor.
info    service/service.go:143     Everything is ready.
```

---

## 📝 Submission Deliverables
To complete today's challenge:
1.  Provide the updated ConfigMap yaml snippet demonstrating your tail-based sampling rules.
2.  Capture your collector logs showing successful configuration parsing.
3.  Inject a payment gateway error and capture a screenshot of the trace in Jaeger proving it was saved by your tail sampling policies.
