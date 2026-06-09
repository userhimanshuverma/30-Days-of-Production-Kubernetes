# 🧪 Lab 1: Deploying Jaeger in Kubernetes

This lab guides you through deploying a production-like Jaeger instance inside a local Kubernetes cluster, understanding its architectural ports, and exploring the Jaeger Query UI.

---

## 🎯 Goal
Deploy Jaeger, verify all endpoints are running, and set up port forwarding to access the dashboard interface.

---

## 🛠️ Step-by-Step Instructions

### Step 1: Examine the Jaeger Manifests
Open `manifests/jaeger-production.yaml`. Note the namespace, container security settings, and environment variables:
*   `SPAN_STORAGE_TYPE=memory`: Configures Jaeger to keep traces in a local RAM ring-buffer.
*   **Security Configuration**: Notice `runAsNonRoot: true` and the dropped capabilities. In production Kubernetes, running Jaeger as `root` (default in many public charts) is an unnecessary security risk.

### Step 2: Apply the Manifests
Create the `observability` namespace and deploy the Jaeger resources:

```bash
kubectl apply -f manifests/jaeger-production.yaml
```

**Expected Output:**
```text
namespace/observability created
deployment.apps/jaeger created
service/jaeger-query created
service/jaeger-collector created
```

### Step 3: Verify Pod Startup
Monitor the Jaeger pod startup progress inside the `observability` namespace:

```bash
kubectl get pods -n observability -w
```

Wait until the pod shows `1/1 Running`. Press `Ctrl+C` to exit. Let's describe the pod to see the status of the liveness and readiness probes:

```bash
kubectl describe deployment jaeger -n observability
```

Notice that the probes target port `14269` (Jaeger Admin Port) which serves `/` to signal component health.

### Step 4: Access the Jaeger Query UI
Jaeger Query runs on port `16686`. To access the interface from your local developer machine, set up a local port-forward:

```bash
kubectl port-forward svc/jaeger-query -n observability 16686:16686
```

**Verify Interface**: Open your browser and navigate to [http://localhost:16686](http://localhost:16686). You should see the empty Jaeger search console.

---

## 🔬 Understanding the Exposed Ports

Jaeger Collector exposes several ports for ingestion. In `jaeger-production.yaml`, the `jaeger-collector` service routes to:

*   **`4317` (gRPC)**: The default standard port for OpenTelemetry Protocol (OTLP).
*   **`4318` (HTTP)**: The HTTP endpoint for OTLP payloads.
*   **`14250` (gRPC)**: Dedicated gRPC ingestion protocol specific to Jaeger's native SDKs/agents.
*   **`14268` (HTTP)**: Legacy endpoint to accept traces from applications submitting directly via HTTP.
*   **`9411` (HTTP)**: Compatibility layer to accept Zipkin format payloads.

---

## 🧹 Cleanup
If you wish to tear down Jaeger at the end of the day:

```bash
kubectl delete -f manifests/jaeger-production.yaml
```

*Proceed to [Lab 2: Setting up OpenTelemetry Collector](lab-2-otel-collector-setup.md).*
