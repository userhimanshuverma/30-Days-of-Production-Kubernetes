# 📈 Day 17: Monitoring with Prometheus & Grafana
### 🏷️ PHASE 3 — OBSERVABILITY & PRODUCTION OPERATIONS

Welcome to Day 17 of the **30 Days of Production Kubernetes** course. Today, we turn our attention to the bedrock of site reliability engineering: **Observability and Monitoring**.

In a production Kubernetes environment, pod scheduling is dynamic, nodes fail, and workloads auto-scale. Operating such systems without high-fidelity metrics is like driving a race car blindfolded. Today, we will learn how to design, deploy, and operate a production-grade metrics pipeline using Prometheus, Grafana, and Alertmanager.

---

## 🗺️ Day 17 Directory Structure

Here is how today's learning resources are organized:
-   [notes/prometheus-grafana-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/notes/prometheus-grafana-deep-dive.md) — Comprehensive technical reference detailing TSDB storage blocks, PromQL aggregations, relabel configuration mechanics, and exporters.
-   [diagrams/monitoring-architecture.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/diagrams/monitoring-architecture.md) — 12 detailed sequence, component, and routing diagrams for metrics pipelines, alert managers, Thanos, and incident lifecycle flows.
-   [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/) — Production-ready manifests:
    -   [prometheus-rbac.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/prometheus-rbac.yaml) — ClusterRole bindings for dynamic endpoints discovery.
    -   [prometheus-config.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/prometheus-config.yaml) — Scrape configurations and Prometheus rule triggers.
    -   [prometheus-deployment.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/prometheus-deployment.yaml) — StatefulSet mapping persistent metrics storage.
    -   [alertmanager-config.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/alertmanager-config.yaml) — Routing matrices for warning vs critical alarms.
    -   [alertmanager-deployment.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/alertmanager-deployment.yaml) — Alertmanager server deployment.
    -   [node-exporter.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/node-exporter.yaml) — DaemonSet to capture physical host parameters.
    -   [kube-state-metrics.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/kube-state-metrics.yaml) — Standard exporter for API Server resources configurations.
    -   [grafana.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/grafana.yaml) — Grafana visualizer with automated datasource provisioning.
    -   [sample-app.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-17/manifests/sample-app.yaml) — Microservice (using `podinfo`) exposing native Prometheus `/metrics`.
-   [labs/](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/) — Step-by-step engineering labs:
    -   [Lab 1: Installing and Configuring Prometheus](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/lab-1-install-prometheus.md)
    -   [Lab 2: Installing and Configuring Grafana](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/lab-2-install-grafana.md)
    -   [Lab 3: Exporters & Application Monitoring](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/lab-3-exporters-and-applications.md)
    -   [Lab 4: Configuring Alerts & Incident Response](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/lab-4-alerts-and-incident-response.md)
-   [production-notes/observability-at-scale.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/production-notes/observability-at-scale.md) — Advanced SRE operations detailing alert fatigue, high cardinality troubleshooting, Thanos architectures, and SLO error budget mathematics.
-   [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/troubleshooting/playbook.md) — Incident playbooks for offline scrape targets, Prometheus memory crashes, alert storms, and sluggish dashboards.
-   [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/exercises/challenges.md) — Code challenges to fix broken endpoints discovery relabel configurations and design PromQL burn-rate alerts.
-   [resources/monitoring-command-center.html](file:///d:/30_Days_of_Production_Kubernetes/Day-17/resources/monitoring-command-center.html) — Futuristic, single-page interactive HTML simulator to experience metrics generation, fault injections (memory leaks, node failure), and Alertmanager routing.

---

## 1. Why Monitoring Matters: Proactive SRE Operations

In traditional, static systems, monitoring was **reactive** (e.g., pinging a virtual machine; if it failed, notify the engineer). In dynamic cloud-native environments, this approach is insufficient.

Modern Site Reliability Engineering (SRE) relies on **proactive operations**:
*   **Early Fault Detection:** Recognizing subtle degradations (such as P99 latency spikes or CPU throttling) before they manifest as outright service failures.
*   **Capacity Forecasting:** Analyzing saturation indicators (like storage growth or JVM memory exhaustion) to schedule nodes and expand clusters prior to resource exhaustions.
*   **Zero-Trust Observability:** Ensuring that every layer of the platform—from physical host network interface to containerized microservice—is exposing telemetry.

### The Metrics Advantage
While **Logs** capture precise details about individual events (critical for post-mortem debugging) and **Traces** map request flow paths across service boundaries, **Metrics** provide aggregate numeric telemetry. Metrics are fast to query, cost-efficient to store, and act as the primary sensor for system health and automated alerts.

---

## 2. Core Metrics Fundamentals

Prometheus processes metrics as numeric time-series streams. Every data point consists of a timestamp, a float64 value, and key-value dimensions (labels).

SREs utilize four core metric abstractions:
1.  **Counters:** Cumulative values that only increase or reset to zero (e.g., `http_requests_total`). Wrap these in `rate()` or `increase()` functions to calculate rates over time.
2.  **Gauges:** Variable indicators that go up and down arbitrarily (e.g., `node_memory_Active_bytes`). Use gauges to monitor current capacity, thread pools, and active sessions.
3.  **Histograms:** Aggregatable buckets that group observation counts (e.g., `http_request_duration_seconds_bucket`). Histograms allow the mathematical calculation of percentiles (like p95 and p99 quantiles) using the `histogram_quantile()` function.
4.  **Summaries:** Client-side calculated quantiles. Useful for precise measurement of single application instances, but cannot be mathematically aggregated across clusters.

---

## 3. Prometheus Deep Dive

Prometheus uses a **pull-based model** (scraping) to collect metrics.

```
┌─────────────────────┐        Scrape (/metrics)        ┌────────────────┐
│ Application / Pod   │ <────────────────────────────── │ Prometheus     │
└─────────────────────┘                                 └────────────────┘
```

*   **TSDB Engine:** Scraped points are committed to an active in-memory buffer (Head block) and logged to an append-only Write-Ahead Log (WAL) to prevent data loss. Every 2 hours, data is compacted and flushed to permanent disk storage blocks.
*   **PromQL:** A powerful query language. To find the per-second rate of HTTP 5xx errors grouped by namespace, you use:
    ```promql
    sum(rate(http_requests_total{status=~"5.."}[5m])) by (kubernetes_namespace)
    ```
*   **Service Discovery:** Prometheus queries the Kubernetes API Server to dynamically discover endpoints, pods, and nodes. By applying `relabel_configs`, it maps dynamic pod metadata into standardized Prometheus labels.

---

## 4. Kubernetes Exporters: Telemetry Providers

To capture metrics from systems that do not expose Prometheus metrics natively, SREs deploy sidecars and daemons called **Exporters**:

*   **Node Exporter:** Runs as a DaemonSet to capture physical or virtual host parameters (disk IOPS, network interfaces, physical RAM, CPU states).
*   **cAdvisor:** Embedded within Kubelet, cAdvisor monitors individual container CPU, memory limits, and page faults.
*   **kube-state-metrics:** A deployment that queries the API Server to export metrics about configurations and scheduling status (unavailable replicas, node readiness, limits vs requests).

---

## 5. Grafana & Dashboard Design

Grafana queries Prometheus using PromQL to build real-time visual dashboards. SREs design dashboards with strict **hierarchy**:

1.  **Executive Overview:** Global SLO availability indicators and user-facing performance signals.
2.  **Service Layers:** Component-specific dashboards mapping database locks, consumer lag in message brokers, or query response times in search engines.
3.  **Infrastructure Layers:** Granular panels showing container CPU throttling, worker node memory saturation, and network packet drop rates.

---

## 6. SRE Golden Signals

When monitoring a service, track the **4 Golden Signals** to evaluate system health:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SRE GOLDEN SIGNALS                               │
├───────────────┬─────────────────────────────────────────────────────────────┤
│ 1. Latency    │ Time taken to service a request (e.g., P99 latency < 200ms).│
├───────────────┼─────────────────────────────────────────────────────────────┤
│ 2. Traffic    │ Demand placed on the service (e.g., HTTP requests/sec).     │
├───────────────┼─────────────────────────────────────────────────────────────┤
│ 3. Errors     │ Rate of requests that fail (e.g., HTTP 5xx responses).       │
├───────────────┼─────────────────────────────────────────────────────────────┤
│ 4. Saturation │ Measure of system fullness (e.g., memory usage vs limits).  │
└───────────────┴─────────────────────────────────────────────────────────────┘
```

---

## 7. Alerting & Routing Matrix

Alerting rules in Prometheus evaluate expressions. If a threshold is breached (e.g., `Errors > 5%`), the alert enters a `PENDING` state. If the breach persists, it transitions to `FIRING` and is routed to **Alertmanager**.

```
[ Firing Alert ] ─► [ Alertmanager ] ─► Grouping & Silences ─► [ PagerDuty / Slack ]
```

*   **Deduplication & Grouping:** Alertmanager combines multiple related alerts (e.g., 50 pods crashing on a failed node) into a single notification context to prevent noise.
*   **Inhibition:** Suppresses secondary warnings if a primary infrastructure alert is already active (e.g., silencing pod CPU alerts when NodeExporterOffline is active).
*   **Routing Trees:** Directs critical alerts (which require immediate action) to PagerDuty or OpsGenie to page the on-call engineer, and warning alerts to Slack or Email.

---

## 8. Real-world Production Examples

Today's notes and manifests cover monitoring configurations for critical cloud-native components:
*   **API Services:** Request rates, latency percentiles, error rates, and HPA autoscaling thresholds.
*   **Kafka Clusters:** Consumer group lags (`kafka_consumergroup_lag`), message partition balances, under-replicated partitions, and disk storage metrics.
*   **PostgreSQL:** Active connections count, transaction commit rates, index scan hit ratios (`pg_stat_user_tables`), and replication delay.
*   **Elasticsearch & Apache Pinot:** Query times, segment counts, memory heap utilization, garbage collection delays, and ingestion rate queues.
*   **Kubernetes Control Plane:** API server request latency, etcd db size, scheduling queue delays, and controller manager sync times.

---

## 🏁 Summary of Daily Tasks

To complete Day 17, proceed with the following steps:
1.  **Review the Diagrams:** Open [diagrams/monitoring-architecture.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/diagrams/monitoring-architecture.md) to study how metric streams flow, service discovery resolves targets, and Alertmanager routes alarms.
2.  **Study Deep-Dive Notes:** Review [notes/prometheus-grafana-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/notes/prometheus-grafana-deep-dive.md) to master PromQL operations, TSDB compacting processes, and exporter subsystems.
3.  **Open the Interactive Simulator:** Launch the [Monitoring Command Center](file:///d:/30_Days_of_Production_Kubernetes/Day-17/resources/monitoring-command-center.html) in your browser. Complete the four simulated SRE missions (normal operations, memory leaks, error page routing, node crashes) to see how observability works.
4.  **Execute the Step-by-Step Labs:**
    *   [Lab 1: Installing and Configuring Prometheus](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/lab-1-install-prometheus.md)
    *   [Lab 2: Installing and Configuring Grafana](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/lab-2-install-grafana.md)
    *   [Lab 3: Exporters & Application Monitoring](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/lab-3-exporters-and-applications.md)
    *   [Lab 4: Configuring Alerts & Incident Response](file:///d:/30_Days_of_Production_Kubernetes/Day-17/labs/lab-4-alerts-and-incident-response.md)
5.  **Study Production Best Practices:** Read [production-notes/observability-at-scale.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/production-notes/observability-at-scale.md) to understand metric downsampling, cardinality explosions, remote write scaling, and SLO burn math.
6.  **Review Troubleshooting runbooks:** Familiarize yourself with command diagnostics for scrape failures, OOM conditions, and query slowness in [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/troubleshooting/playbook.md).
7.  **Complete the Challenges:** Open [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-17/exercises/challenges.md) and solve the scrape target relabeling problem and PromQL SLO burn alert design challenge.
