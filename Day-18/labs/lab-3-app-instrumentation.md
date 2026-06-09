# 🧪 Lab 3: Instrumenting Microservices & Context Propagation

In this lab, you will learn how applications are instrumented in Go, Python, and Node.js to register OpenTelemetry tracers, create custom spans, and propagate context across network boundaries. You will also deploy a two-tier microservices app to generate real traces.

---

## 🎯 Goal
Understand code-level instrumentation, deploy instrumented mock services, generate mock transactions, and watch trace context propagate in real-time.

---

## 💻 Instrumentation Code Patterns

### 1. Go (gRPC / HTTP API Instrumentation)
To instrument a Go microservice, you configure a global `TracerProvider`, load the standard W3C propagator, and wrap outgoing and incoming HTTP handlers:

```go
package main

import (
	"context"
	"net/http"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func initTracer() (*sdktrace.TracerProvider, error) {
	// 1. Create HTTP OTLP Exporter pointing to the Collector
	exporter, err := otlptracehttp.New(context.Background())
	if err != nil {
		return nil, err
	}

	// 2. Build resource descriptor containing service tags
	res, err := resource.New(context.Background(),
		resource.WithAttributes(semconv.ServiceNameKey.String("order-processor")),
	)

	// 3. Register the SDK Tracer Provider with BatchSpanProcessor
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	
	// 4. Register W3C standard propagator as default
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, 
		propagation.Baggage{},
	))
	
	return tp, nil
}

func main() {
	tp, _ := initTracer()
	defer tp.Shutdown(context.Background())

	// 5. Auto-instrument incoming HTTP router calls
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Order Completed"))
	})
	
	otelHandler := otelhttp.NewHandler(handler, "http.recv")
	http.ListenAndServe(":8080", otelHandler)
}
```

---

### 2. Python (FastAPI Middleware Instrumentation)
Python applications utilize auto-instrumentation packages or express middlewares to manage parent contexts:

```python
from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# 1. Initialize global Tracer Provider
provider = TracerProvider()
processor = BatchSpanProcessor(OTLPSpanExporter(endpoint="http://otel-collector.observability.svc:4317"))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

app = FastAPI()

# 2. Instrument application endpoints
FastAPIInstrumentor.instrument_app(app)

@app.get("/checkout")
def checkout():
    # 3. Create a manual sub-span for DB checkout validation
    tracer = trace.get_tracer(__name__)
    with tracer.start_as_current_span("validate_cart_items") as span:
        span.set_attribute("cart.id", 44211)
        # business logic goes here
        return {"status": "success"}
```

---

### 3. Node.js (Express Instrumentation)
Node.js uses an initialization script loaded before the main app starts, binding to module loaders to intercept standard HTTP/Database calls:

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
const { ExpressInstrumentation } = require('@opentelemetry/instrumentation-express');

// Initialize the OTel Node SDK
const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    endpoint: 'grpc://otel-collector.observability.svc:4317',
  }),
  instrumentations: [
    new HttpInstrumentation(),
    new ExpressInstrumentation()
  ],
  serviceName: 'web-frontend',
});

sdk.start();
```

---

## 🛠️ Step-by-Step Hands-On Deployment

Now, deploy the pre-built, instrumented mock applications to see this code work in your cluster.

### Step 1: Apply Microservices App Manifests
Deploy the frontend and backend deployments and service configurations:

```bash
kubectl apply -f manifests/microservices-app.yaml
```

**Expected Output:**
```text
deployment.apps/tracing-frontend created
service/tracing-frontend created
deployment.apps/tracing-backend created
service/tracing-backend created
```

Wait for pods to reach `Running` status:
```bash
kubectl get pods -n default
```

### Step 2: Set Up Traffic Port Forwarding
Open a terminal and map port `8080` to access the Frontend microservice:

```bash
kubectl port-forward svc/tracing-frontend 8080:80
```

### Step 3: Generate Telemetry Traffic
Using a separate command prompt, run several curl commands to generate requests. The mock app is programmed to propagate headers down to the backend order processor:

```bash
curl http://localhost:8080/
curl http://localhost:8080/
curl http://localhost:8080/
```

### Step 4: Verify Collector Log Output
Examine the logs of your OpenTelemetry Collector. Because the `logging` exporter is active in `otel-collector.yaml`, the collector output registers incoming spans:

```bash
kubectl logs -n observability -l app=otel-collector -c otel-collector --tail=100
```

You should see logs showing incoming trace events containing span tags:
```text
Span #0
    Trace ID       : 6ea7b1d9bf5b8f2c3111b222c019a86b
    Parent ID      : 99120de840cb1f09
    ID             : 1100f7e1b101c448
    Name           : order-processor:create-db-record
    Kind           : SPAN_KIND_INTERNAL
    Attributes:
         -> db.system: STRING(postgresql)
         -> db.name: STRING(orders)
```

### Step 5: Search the Trace in Jaeger UI
1.  Open your Jaeger port-forward from Lab 1: [http://localhost:16686](http://localhost:16686).
2.  Refresh the page, click the **Service** dropdown, select `frontend` or `order-processor`.
3.  Click **Find Traces**.
4.  Select a trace to open the Gantt chart rendering. Notice that clicking a span displays details such as HTTP target paths, status codes, and server IPs.

*Proceed to [Lab 4: Latency & Bottleneck Analysis](lab-4-performance-debugging.md).*
