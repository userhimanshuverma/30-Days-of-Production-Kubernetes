# Prometheus Optimization: Managing Metric Cardinality & Memory Churn

This guide details best practices for scaling Prometheus scrape loops and minimizing memory usage in high-throughput clusters.

---

## ⚠️ The Threat of High Cardinality
In Prometheus, every unique combination of key-value labels creates a distinct time-series stream. High-cardinality label values (e.g. including UUIDs, user IDs, request path variables, or ephemeral container IDs in metric labels) cause database indexes to balloon, leading to out-of-memory crashes (OOM) on Prometheus pods.

---

## 🛠️ Relabel Configurations: Dropping High-Cardinality Metrics

To prevent index bloat, configure metric relabelings inside Prometheus `ServiceMonitor` definitions to filter out unnecessary or high-cardinality metrics before they are written to disk.

### Example: Dropping ephemeral transaction routes
```yaml
spec:
  endpoints:
    - port: metrics
      metricRelabelings:
        # Drop high-cardinality request metrics containing path IDs
        - sourceLabels: [__name__, path]
          regex: "http_request_duration_seconds_bucket;/api/v1/users/.*"
          action: drop
        # Keep only specific metrics to save disk space
        - sourceLabels: [__name__]
          regex: "(http_requests_total|http_request_duration_seconds_bucket|up)"
          action: keep
```

---

## ⚙️ Memory Tuning Recommendations

1.  **Adjust Scrape Intervals**: In production, default scrape intervals of 15 seconds may be too aggressive for non-critical workloads. Set background stateful services to 30s or 60s scrape intervals.
    ```yaml
    scrape_interval: 30s
    evaluation_interval: 30s
    ```
2.  **Configure TSDB Retention policies**: Enforce hard limits on both duration and maximum disk size:
    ```bash
    --storage.tsdb.retention.time=15d
    --storage.tsdb.retention.size=50GB
    ```
3.  **Audit label scopes**: Never include labels generated dynamically by external clients (e.g. `user_agent`, `session_token`). Keep labels bounded by static enum values.
