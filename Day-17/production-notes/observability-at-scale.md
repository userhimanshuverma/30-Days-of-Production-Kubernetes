# ⚡ Day 17 Production Notes: Observability at Scale (SRE Lessons Learned)

Operating monitoring platforms for thousands of microservices and multi-million metric streams reveals scaling challenges that do not appear in small lab setups. This document contains senior-level operational lessons, engineering patterns, and mathematical models for building sustainable, high-performance monitoring pipelines.

---

## 1. Alert Fatigue & SLO-Based Alerting

In many legacy systems, engineers configure alert rules for system thresholds:
*   `cpu_usage > 85%`
*   `memory_usage > 90%`
*   `disk_usage > 80%`

In production, these alerts lead directly to **alert fatigue**. CPU usage can spike to 95% during normal operations (e.g., cron jobs, garbage collection) and resolve without impact on users. When an alert rings 20 times a day without requiring action, engineers learn to ignore it. A critical outage is then missed when it occurs.

### Google SRE Rules of Alerting
1.  **Alert on symptoms, not causes:** A high CPU utilization is a cause. High HTTP latency or HTTP 5xx errors are symptoms that users are actually suffering.
2.  **Every page must require manual intervention:** If an alert is auto-resolvable or requires no immediate human action, it should be a warning email or a Slack post, never a pager alert.
3.  **Alert on SLO Burn Rates:**

### SLO, SLI, and Error Budget Math

Instead of alert rules on raw thresholds, modern SRE uses **SLO Burn Rate Alerting**. 
*   **SLI (Service Level Indicator):** A metric measuring service level. E.g., `(Successful Requests) / (Total Requests)`.
*   **SLO (Service Level Objective):** A target reliability percentage over a rolling window. E.g., `99.9% availability over 30 days`.
*   **Error Budget:** The allowed unreliability. `Error Budget = 100% - SLO`. For a 99.9% SLO, the error budget is `0.1%`. If a service receives 1,000,000 requests in 30 days, we are allowed 1,000 failed requests before breaching the SLO.
*   **Burn Rate:** The speed at which a service consumes its error budget.
    *   **Burn Rate = 1:** Consumes 100% of the budget in exactly the target window (e.g., 30 days).
    *   **Burn Rate = 14.4:** Consumes 10% of the budget in 5 hours, or 100% in 50 hours.
    *   **Burn Rate = 14.4 Alert Rule:**

$$\text{SLI Error Rate} > (1 - \text{SLO}) \times \text{Burn Rate}$$

For a $99.9\%$ SLO ($0.001$ allowed error rate) and a Burn Rate of $14.4$ (which consumes $10\%$ of our budget in 5 hours, triggering a critical page):

$$\text{Error Rate} > 0.001 \times 14.4 = 1.44\%$$

If the HTTP error rate exceeds $1.44\%$ for 1 hour, we page the SRE. This prevents transient 100% spikes from waking people up, while ensuring sustained degradations are caught long before the monthly SLO is breached.

---

## 2. High Cardinality Disasters

A single time-series is uniquely identified by the metric name plus its labels:
`http_requests_total{service="api", method="POST", status="200"}`

**High Cardinality** refers to labels that have a large or infinite number of unique values.

### The Anti-Pattern
A developer instruments an application tracking user logins, adding the `user_id` as a label:
`user_login_events_total{user_id="103984920"}`

If the service has 5 million users, Prometheus must create **5 million unique time-series index entries** in memory.

### The Impact
1.  **Memory Exhaustion (OOM):** The Prometheus index cache explodes in size. The container runs out of RAM and is killed (`OOMKilled`).
2.  **Slow Queries:** Queries over large time windows stall because Prometheus must scan millions of individual index blocks.
3.  **Storage Saturation:** The disk WAL grows rapidly, leading to write blocks and lost metrics.

### How to Detect Cardinality Issues
Query Prometheus's metadata API or use PromQL to find the highest cardinality labels:
```promql
# Count active time-series per metric name
count by (__name__) ({__name__=~".+"})

# Find which metrics have the highest label set count
topk(10, count by (__name__) ({__name__=~".+"}))
```

### Remediation & Prevention
*   **Move high-cardinality metadata to logs:** User IDs, transaction IDs, order numbers, and email addresses belong in elasticsearch/loki logs, not Prometheus labels.
*   **Apply relabeling drop rules:** Drop metric labels in Prometheus configs using the `labeldrop` action if a third-party application exposes dynamic labels.
*   **Set series limits:** Configure `sample_limit` in the scrape configurations to automatically drop scrape jobs that exceed a configured limit (e.g., 50,000 metrics per scrape).

---

## 3. Prometheus Scaling Architectures

A single Prometheus instance can comfortably scale to scrape several hundred thousand metrics per second. Beyond that, a single pod's memory and CPU limits become bottleneck constraints.

### 1. Prometheus Agent Mode
Introduced in v2.32.0, Agent Mode optimizes Prometheus to act strictly as a metrics forwarder:
*   Disables the local database querying engine, rule evaluator, and historical chunk storage.
*   Retains the scraper, service discovery, and a short-term local WAL buffer.
*   Stream-pipes metrics immediately to a centralized long-term storage server via **Remote Write**.
*   Reduces memory usage by up to **80%**, making it ideal for distributed agent deployment across thousands of remote edge clusters.

### 2. Multi-Cluster Observability Platforms

To build a centralized, single-pane-of-glass monitoring system across multiple clusters, organizations deploy long-term storage engines:

```
  ┌─────────────────┐
  │ Cluster A Node  │ ──(Remote Write)──┐
  └─────────────────┘                  │
  ┌─────────────────┐                  ▼
  │ Cluster B Node  │ ──(Remote Write)──┼─► [ Thanos / Cortex / Mimir Hub ]
  └─────────────────┘                  ▲
  ┌─────────────────┐                  │
  │ Cluster C Node  │ ──(Remote Write)──┘
  └─────────────────┘
```

#### Thanos
Thanos integrates with existing Prometheus instances:
*   **Thanos Sidecar:** Runs next to Prometheus, uploading compacted 2-hour blocks to Object Storage (S3/GCS).
*   **Thanos Store:** Serves historical metrics directly from Object Storage.
*   **Thanos Query:** A stateless service that aggregates and de-duplicates metrics from multiple sidecars and store gateways, exposing a single PromQL endpoint for Grafana.

#### Cortex / Grafana Mimir
A multi-tenant, horizontally scalable database built specifically to ingest metrics via Remote Write:
*   Accepts metric streams from Prometheus agents.
*   Splits time-series indices and chunks across a distributed cluster of indexers and store gateways.
*   Uses NoSQL databases or Object Storage backends for extreme scale (billions of metrics).

---

## 4. Cost Optimization & Metric Pruning

Ingesting and storing metrics costs money (network bandwidth, RAM, cloud storage). On average, **30% to 50% of metrics scraped in enterprise environments are never queried**.

### Cost Reduction Patterns

#### 1. Prune unused cAdvisor metrics
cAdvisor exposes extensive metrics for every container. Drop metrics you don't use:
```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: "(container_tasks_state|container_memory_failures_total|container_sockets|container_threads)"
    action: drop
```

#### 2. Drop metrics from sidecar containers
Istio, Linkerd, and CloudSQL proxy sidecars generate thousands of metrics per container. Drop metrics relating to sidecars if you only care about the primary application metric:
```yaml
metric_relabel_configs:
  - source_labels: [container]
    regex: "(istio-proxy|cloudsql-proxy)"
    action: drop
```

#### 3. Standardize Scraping Intervals
Avoid scraping everything at 5-second intervals. 
*   **Production apps:** 15s to 30s scrape interval.
*   **Dev/Staging apps:** 60s scrape interval.
*   **Long-running batch jobs:** 2m to 5m scrape interval.

#### 4. Configure Downsampling in Thanos/Mimir
Instead of storing raw 15-second data points forever, downsample historical data:
*   Keep raw metrics for **14 days**.
*   Downsample to **5-minute resolution** for storage up to **90 days**.
*   Downsample to **1-hour resolution** for storage beyond **90 days**.
*   Downsampling reduces index sizes by **90%**, significantly speeding up 1-year historical range queries in Grafana.
