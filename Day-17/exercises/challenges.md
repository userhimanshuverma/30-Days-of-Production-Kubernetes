# 🏆 Day 17 Exercises & Challenges

Test your observability skills with these production scenarios. You will diagnose a broken scrape configuration and design an SLO burn-rate alerting rule.

---

## Challenge 1: The Invisible Exporter (Scrape Diagnostics)

### Scenario
You have deployed a custom Go backend service named `payment-processor` in the `payments` namespace. The application contains an embedded Prometheus metrics library configured to expose metrics on port `9090` at the path `/metrics`. 

You have annotated the Service object as follows:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: payment-processor
  namespace: payments
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
    prometheus.io/path: "/metrics"
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 9090
  selector:
    app: payment-processor
```

However, when checking the Prometheus Targets dashboard, the service is not listed. Prometheus is not scraping the service at all.

### Your Tasks
1.  Review the `kubernetes-service-endpoints` scrape configuration in the `prometheus-config.yaml` file:
    ```yaml
    - job_name: "kubernetes-service-endpoints"
      kubernetes_sd_configs:
        - role: endpoints
      relabel_configs:
        - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
          action: keep
          regex: "true"
        - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
          action: replace
          target_label: __address__
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
    ```
2.  Examine the service annotations and ports. Identify why the endpoints role fails to resolve the correct target address.
3.  Write the corrected Service manifest or explain the modifications required to make the scraper discover the service endpoints.

### Solution Walkthrough
*   **The Problem:** The `kubernetes-service-endpoints` job uses the `endpoints` role for service discovery. An endpoints object contains the IP addresses of backing pods, mapping to their container port (in this case, targetPort `9090`). However, endpoint service discovery labels dynamic ports based on the Service's spec ports.
*   The relabel rule for port extraction checks:
    `source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]`
    If targetPort is `9090` but the Service port is `8080`, and the annotation specifies `9090`, then:
    *   `__address__` originally defaults to `<pod-ip>:9090` (as endpoints map pod ports).
    *   The relabel rule matches `regex: ([^:]+)(?::\d+)?;(\d+)` and replaces it with `$1:$2`, where `$2` is the port from the annotation (`9090`). This results in `<pod-ip>:9090`.
    *   **The Trap:** If targetPort is specified as a named port in the service but isn't matched, or if there is a mismatch where the pod container itself isn't exposed properly, endpoints won't bind. In this scenario, the primary issue is that Prometheus only scrapes ports exposed *on the endpoints object*. If the pod template doesn't explicitly declare `containerPort: 9090`, Kubernetes won't expose it in the endpoints list.
*   **The Fix:** 
    1.  Ensure the Pod template manifest explicitly declares the containerPort:
        ```yaml
        spec:
          containers:
            - name: processor
              image: payment-image
              ports:
                - containerPort: 9090
                  name: metrics-port
        ```
    2.  Alternatively, use Pod Service Discovery (`role: pod`) instead of Endpoints Discovery if scraping individual pods directly, bypassing Service ports.

---

## Challenge 2: SLO Burn-Rate Alerting (PromQL Design)

### Scenario
You are the Lead SRE for a Kubernetes-hosted e-commerce catalog API. You need to write a production-grade alerting rule to page the on-call engineer when the service's error budget is burning too quickly.

Here are the specifications:
*   **Metric Name:** `http_requests_total{service="catalog-api", status="..."}`
*   **SLO:** $99.9\%$ availability over a rolling 30-day window.
*   **Critical Alarm Threshold:** The service is consuming more than $2\%$ of its total monthly error budget in a single **1-hour** window.
*   **Mathematical Calculation:**
    *   A monthly error budget permits $0.1\%$ ($0.001$) error rate.
    *   Consuming $2\%$ of the monthly budget in 1 hour is equivalent to a **burn rate of 14.4** ($0.02 \times 720 \text{ hours in a month} = 14.4$).
    *   The per-second error rate over 1 hour must exceed:

$$\text{Error Rate} > 0.001 \times 14.4 = 0.0144 \text{ (or } 1.44\% \text{)}$$

### Your Tasks
1.  Write the complete PromQL expression that calculates the ratio of HTTP 5xx errors to total HTTP requests for the `catalog-api` service over the last 1 hour.
2.  Incorporate the burn rate threshold ($1.44\%$) to complete the expression.
3.  Format the PromQL expression as a valid Kubernetes PrometheusRule yaml block, including labels and annotations (summary and description).

### Solution Walkthought & Answer
The ratio of 5xx errors to total requests over a 1-hour window is:

```promql
sum(rate(http_requests_total{service="catalog-api", status=~"5.."}[1h])) 
/ 
sum(rate(http_requests_total{service="catalog-api"}[1h]))
```

Multiplying this by 100 calculates the percentage. For the alert threshold ($1.44\%$, or $0.0144$ ratio):

```promql
(
  sum(rate(http_requests_total{service="catalog-api", status=~"5.."}[1h])) 
  / 
  sum(rate(http_requests_total{service="catalog-api"}[1h]))
) > 0.0144
```

Here is the complete `PrometheusRule` manifest:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: catalog-api-slo-alerts
  namespace: default
  labels:
    role: alert-rules
spec:
  groups:
    - name: catalog-slo
      rules:
        - alert: CatalogApiHighBurnRate1h
          expr: |
            (
              sum(rate(http_requests_total{service="catalog-api", status=~"5.."}[1h]))
              /
              sum(rate(http_requests_total{service="catalog-api"}[1h]))
            ) > 0.0144
          for: 5m
          labels:
            severity: critical
            tier: api
          annotations:
            summary: "Catalog API 1-hour error budget burn rate exceeds 14.4"
            description: "The catalog-api service is consuming more than 2% of its monthly error budget in a single hour. Current error rate is above 1.44% (value: {{ $value | printf \"%.4f\" }})."
```
