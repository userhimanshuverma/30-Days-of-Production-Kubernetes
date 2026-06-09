# 🧪 Lab 2: Setting up OpenTelemetry Collector

In this lab, you will deploy the OpenTelemetry Collector inside your Kubernetes cluster. You will learn how the Collector uses a pipeline model to process telemetry data and routing.

---

## 🎯 Goal
Configure and deploy the OTel Collector, verify its ingestion pipeline, and confirm it can forward data to Jaeger.

---

## 🛠️ Step-by-Step Instructions

### Step 1: Analyze the Collector Pipeline Configuration
Open `manifests/otel-collector.yaml` and look at the ConfigMap `otel-collector-config`. Notice how the pipeline is defined:

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, filter/healthz, batch]
      exporters: [otlp/jaeger, logging]
```

This configuration forms a standard DAG processing engine:
1.  **Receivers**: `otlp` is active, listening on port `4317` (gRPC) and `4318` (HTTP) inside the cluster.
2.  **Processors**:
    *   `memory_limiter`: Safeguards collector memory boundaries.
    *   `filter/healthz`: Explicitly drops trace spans targeting `/healthz` or `/metrics` to avoid polluting our databases with noisy, automated probe calls.
    *   `batch`: Collects spans in memory and flushes them in batches, reducing network overhead.
3.  **Exporters**:
    *   `otlp/jaeger`: Standard OTLP gRPC export targeting the service `jaeger-collector.observability:4317`.
    *   `logging`: Outputs span summaries directly into the collector pod container stdout (perfect for debugging).

---

### Step 2: Deploy the OTel Collector Gateway
Deploy the ServiceAccount, ClusterRoles, ConfigMap, Deployment, and Service:

```bash
kubectl apply -f manifests/otel-collector.yaml
```

**Expected Output:**
```text
serviceaccount/otel-collector created
clusterrole.rbac.authorization.k8s.io/otel-collector created
clusterrolebinding.rbac.authorization.k8s.io/otel-collector created
configmap/otel-collector-config created
deployment.apps/otel-collector created
service/otel-collector created
```

---

### Step 3: Verify Collector Status & Listeners
Ensure the OTel Collector starts without errors:

```bash
kubectl get pods -n observability -l app=otel-collector
```

Wait until status is `Running`. Check the collector startup logs to confirm the pipelines started:

```bash
kubectl logs -n observability -l app=otel-collector --tail=50
```

Look for lines indicating successful pipeline instantiation:
```text
info    service/telemetry.go:84    Setting up telemetry...
info    service/pipelines.go:120   Traces pipeline started.
info    service/service.go:143     Everything is ready. Begin running.
```

---

### Step 4: Verify Ports
Run the following to verify that the internal ClusterIP service has mapped the ports properly:

```bash
kubectl get svc -n observability otel-collector
```

This service exposes port `4317` and `4318` within the cluster network, allowing any microservice in any namespace to point its SDK variables to `http://otel-collector.observability.svc.cluster.local:4318`.

*Proceed to [Lab 3: Instrumenting Microservices & Context Propagation](lab-3-app-instrumentation.md).*
