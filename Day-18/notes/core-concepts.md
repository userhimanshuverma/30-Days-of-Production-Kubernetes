# 📝 Deep Dive: Core Concepts in Distributed Tracing

This document provides a rigorous technical breakdown of the specifications and concepts underlying OpenTelemetry and modern distributed tracing.

---

## ⚡ The Anatomy of a Span

A span represents a single operation or unit of work. Every span contains the following structural components:

```
+--------------------------------------------------------------+
| Span Name: "SELECT * FROM users WHERE id = ?"                |
+--------------------------------------------------------------+
| SpanContext:                                                 |
|   TraceID:  4bf92f3577b34da6a3ce929d0e0e4736                 |
|   SpanID:   00f067aa0ba902b7                                 |
|   ParentID: c53be9ad11f930e1                                 |
|   Flags:    01 (Sampled)                                     |
+--------------------------------------------------------------+
| Timestamps:                                                  |
|   Start: 2026-06-09T20:12:00.001Z                            |
|   End:   2026-06-09T20:12:00.012Z (Duration: 11ms)           |
+--------------------------------------------------------------+
| Attributes:                                                  |
|   db.system = "postgresql"                                   |
|   db.name = "prod_users"                                     |
|   net.peer.name = "db-primary.internal"                      |
+--------------------------------------------------------------+
| Events:                                                      |
|   [20:12:00.002Z] "connection_acquired"                      |
|   [20:12:00.010Z] "db_parse_complete"                        |
+--------------------------------------------------------------+
| Status: StatusCode = OK, StatusDescription = ""              |
+--------------------------------------------------------------+
```

### Attributes vs. Events
Understanding when to use Attributes versus Events is a common point of confusion:

*   **Attributes**: Applied directly to the span. These are key-value pairs used to store metadata about the *entire operation*. They are indexed by tracing backends, enabling searches like: `"Find all spans where db.system = 'postgresql' and latency > 500ms"`.
*   **Events**: Think of these as inline, structured logs *within* a span. They represent a single point in time during the span's execution. They cannot be used to query/index traces at a high level, but are vital for timeline analysis (e.g., measuring exactly how long was spent waiting to acquire a database connection).

---

## 🔗 Context Propagation & W3C Trace Context

To coordinate spans across distributed systems, trace metadata must cross process boundaries. This is known as **Context Propagation**.

Context propagation consists of two operations:
1.  **Inject**: The client library serializes the current `SpanContext` (Trace ID, Span ID, Flags) into the request carrier (e.g., HTTP headers, gRPC metadata, RabbitMQ headers).
2.  **Extract**: The receiving service's middleware intercepts the request, deserializes the headers, and sets up a new local `Span` that references the extracted context as its **Parent**.

### W3C Trace Context Standard
OpenTelemetry defaults to the standard W3C Trace Context headers. This ensures interoperability across different tracing libraries and vendors.

#### The `traceparent` Header
This header contains the minimal data required to link spans together:
```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             │  └──────────────┬───────────────┘ └──────┬──────┘ └─┬┘
             │                 │                        │          └── Trace Flags
             │                 │                        └───────────── Parent Span ID
             │                 └────────────────────────────────────── Trace ID
             └──────────────────────────────────────────────────────── Version
```

*   **Version**: Indicates the specification version (currently `00`).
*   **Trace ID**: A 16-byte hex-encoded string (32 characters), globally unique across all spans.
*   **Parent Span ID**: An 8-byte hex-encoded string (16 characters) representing the span that initiated the outbound call.
*   **Trace Flags**: 8-bits representing sampling options. `01` means "sampled" (record trace); `00` means "not sampled" (ignore).

#### The `tracestate` Header
This companion header provides auxiliary key-value pairs for vendor-specific metadata or internal system state. For example:
```
tracestate: congo=t61rcWkgMzE,rojo=00f067a
```
This allows proprietary trace ID mappings or custom routing flags to coexist safely alongside standard W3C formats.

---

## 🏗️ OpenTelemetry: The API vs. SDK Boundary

One of OpenTelemetry's core design principles is the strict separation between the **API** and the **SDK**.

```
+-----------------------------------------------------------------+
|                        Application Code                         |
+-----------------------------------------------------------------+
                                |
                                v
+-----------------------------------------------------------------+
|                       OpenTelemetry API                         |
|   - TracerProvider / Tracer interface                           |
|   - Context Propagation interface                               |
|   - Zero-dependency, lightweight, stub implementation           |
+-----------------------------------------------------------------+
                                |
                                v
+-----------------------------------------------------------------+
|                       OpenTelemetry SDK                         |
|   - In-memory buffering (BatchSpanProcessor)                    |
|   - Exporters (OTLP/gRPC, Jaeger, Prometheus)                   |
|   - Samplers (AlwaysOn, AlwaysOff, ParentBased)                 |
|   - Resource configuration (K8s pod name, host IP)             |
+-----------------------------------------------------------------+
```

### Why this division matters:
1.  **Dependency Safety for Libraries**: Library developers (e.g., an ORM or an HTTP client author) compile their libraries against the **OTel API** only. They do not pull in heavy transport dependencies like gRPC or Protobuf, which are needed for exporters. If the final application developer does not register an SDK, the API simply drops the span calls silently with zero CPU/Memory overhead.
2.  **Plugin-oriented Configuration**: The application entry point (main function) imports and registers the **OTel SDK**, binding concrete exporters, samplers, and processors. This separation allows changing tracing backends (e.g., from Jaeger to Datadog) purely by changing the SDK configuration in `main.go` or `index.js`, without altering a single line of instrumentation code in the business logic or libraries.

---

## 🏷️ Semantic Conventions (SemConv)

In distributed tracing, consistency of attributes is paramount. If one developer names a PostgreSQL database attribute `db.database`, another names it `database_name`, and a third names it `pg.db`, it is impossible to write cross-service alert rules or search queries.

OpenTelemetry defines **Semantic Conventions (SemConv)**—a standardized dictionary of attribute names and values for common technologies:

| Category | Prefix | Example Attribute Keys |
| :--- | :--- | :--- |
| **HTTP** | `http.*` | `http.method`, `http.status_code`, `http.user_agent`, `http.target` |
| **Database** | `db.*` | `db.system`, `db.statement`, `db.user`, `db.connection_string` |
| **Messaging** | `messaging.*` | `messaging.system`, `messaging.destination`, `messaging.operation` |
| **Kubernetes** | `k8s.*` | `k8s.pod.name`, `k8s.namespace.name`, `k8s.container.name` |
| **Host** | `host.*` | `host.name`, `host.id`, `host.arch`, `host.os.type` |

Always adhere strictly to these conventions when manually instrumenting code. Tracing backends rely on these conventions to automatically build dashboard visualizations (like mapping HTTP error rate directly from `http.status_code`).

---

## 💼 Baggage: Propagating Custom Metadata

While standard tracing context relates strictly to *linking execution paths*, **Baggage** is a separate container of key-value pairs carried in-band along the API request context.

### What is it?
Baggage allows you to propagate custom context (e.g., `tenant_id`, `customer_tier = premium`, `request_initiator = mobile`) down the execution tree.

*   Unlike span attributes, which are local to the span they are set on, **Baggage variables automatically propagate to all descendant spans, even across network boundaries**.
*   Baggage is serialized as HTTP headers (`baggage: userId=alice,serverNode=west`).

### ⚠️ Critical SRE Warning: Baggage Overhead
Baggage can be dangerous in production:
1.  **Network Overhead**: Because Baggage is passed inside the HTTP request headers of every subsequent call, attaching large payloads (like large JSON user profiles) will degrade network throughput and trigger HTTP header size limit exceptions (`413 Payload Too Large`).
2.  **Security/Privacy**: Baggage propagates automatically across network paths. If you call external APIs (third-party payment gateways, vendors), your internal baggage (which might contain sensitive data like usernames or tenant IDs) will be sent to them.
3.  **Read-Only Downstream**: Downstream services can read baggage, but modifications or additions are local to their context and do not propagate backwards to the parent service.

*Next: Learn how to manage the performance overhead and sample these traces in the [scaling-and-sampling.md](../production-notes/scaling-and-sampling.md) guide.*
