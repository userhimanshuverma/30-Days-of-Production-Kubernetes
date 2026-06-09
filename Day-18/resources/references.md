# 📚 References and Recommended Reading

Expand your tracing knowledge with this curated list of official specifications, deployment charts, and foundational research papers.

---

## 🔌 Official Specifications & Documentation

1.  **OpenTelemetry Core Documentation**:
    *   [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/otel/)
    *   [OTel Collector Contrib Repository](https://github.com/open-telemetry/opentelemetry-collector-contrib) (The source of custom processors, receivers, and exporters)
2.  **Context Propagation Standard**:
    *   [W3C Trace Context Recommendation](https://www.w3.org/TR/trace-context/)
    *   [W3C Baggage Specification](https://www.w3.org/TR/baggage/)
3.  **Jaeger Deployment & Operations**:
    *   [Jaeger Architecture Documentation](https://www.jaegertracing.io/docs/)
    *   [Jaeger Helm Charts](https://github.com/jaegertracing/helm-charts)

---

## 🏛️ Foundational Research & Case Studies

*   **Google Dapper Paper (2010)**:
    *   [Dapper, a Large-Scale Distributed Systems Tracing Infrastructure](https://research.google/pubs/dapper-a-large-scale-distributed-systems-tracing-infrastructure/)
    *   *Why read this?* This is the original academic paper that defined the modern tracing paradigm (trace IDs, spans, annotation timelines, context propagation) and paved the way for OpenTracing, Zipkin, and Jaeger.
*   **Uber's Jaeger Migration**:
    *   [Evolving Distributed Tracing at Uber](https://www.uber.com/blog/distributed-tracing/)
    *   *Why read this?* A real-world overview of how Uber transitioned from Zipkin to Jaeger, detailing the performance and network bottlenecks they encountered at scale.

---

## 📊 Semantic Conventions (Quick Lookup)

*   [OTel Database Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/database/database-spans/)
*   [OTel HTTP Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/http/http-spans/)
*   [OTel Kubernetes Resource Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/resource/k8s/)
