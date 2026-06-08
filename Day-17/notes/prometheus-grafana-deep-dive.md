# 📖 Day 17 Notes: Prometheus & Grafana Deep Dive

To run Kubernetes platforms reliably at scale, engineers must treat observability not as an afterthought, but as core infrastructure. This document provides a deep, production-grade dive into Prometheus, Grafana, dynamic service discovery, PromQL, and the architectural components that form a metrics monitoring pipeline.

---

## 1. Why Monitoring Matters: Proactive vs. Reactive SRE

In high-velocity Kubernetes environments, the state of the cluster is dynamic. Pods are rescheduled, deployments auto-scale, nodes fail, and microservices interact in complex dependency graphs. 

Traditional monitoring relied on **reactive alerting** (e.g., "ping the server; if it fails to respond, alert the SRE"). In a distributed system, this approach is insufficient: by the time a service stops responding, the business has already lost revenue, and user experience has degraded.

Modern site reliability engineering (SRE) focuses on **proactive operations**:
*   **Predicting Outages:** Monitoring saturation trends (e.g., disk filling, memory leaks) to intervene *before* failures occur.
*   **Observing the User Experience:** Using Service Level Indicators (SLIs) like p99 latency to identify performance degradations before complete downtime.
*   **Rapid Triage:** Providing granular, multi-dimensional query capabilities to isolate root causes in seconds, rather than digging through raw log lines.

### Metrics vs. Logs vs. Traces

Observability is traditionally split into the "three pillars," each serving a specific diagnostic purpose:

| Attribute | Metrics (Time-Series) | Logs (Events) | Traces (Request Paths) |
|---|---|---|---|
| **Data Structure** | Numeric values with timestamps and key-value labels. | Text string messages with metadata. | Spans linked in a directed acyclic graph (DAG). |
| **Typical Size** | Very small (bytes per data point). | Large (megabytes to gigabytes per pod). | Moderate to large. |
| **Storage Cost** | Low; easily compressed and downsampled. | High; requires indexing engines. | High; usually requires sampling. |
| **Query Speed** | Sub-second across millions of points. | Slow; search engine indexes. | Moderate; depends on tracing index. |
| **Best Used For** | Incident detection, SLO tracking, dashboard dashboards. | Root-cause analysis, stack trace debugging. | Bottleneck detection, microservice hops. |

---

## 2. Metrics Fundamentals

Prometheus stores metrics as **time-series**: streams of numeric values recorded at sequential intervals, mapped to a unique name and key-value label pairs (dimensions).

### The Four Prometheus Metric Types

Every metric exposed by an application or exporter falls into one of four categories in the Prometheus SDK:

#### 1. Counter
A cumulative metric that **only increases or resets to zero** on application restart. It represents counts of events.
*   **Common examples:** `http_requests_total`, `process_cpu_seconds_total`, `api_failures_total`.
*   **Usage:** Never query raw counter values. Because counters reset on restarts, always wrap them in functions like `rate()` or `increase()` to compute events per second or totals over a time window.

#### 2. Gauge
A metric that represents a single numerical value that can **arbitrarily go up or down**.
*   **Common examples:** `node_memory_Active_bytes`, `kube_pod_status_phase` (represented as 0/1 state), `go_goroutines`.
*   **Usage:** Gauges are useful for current state measurements. You can use aggregations like `avg()` or `max()`, and functions like `predict_linear()` to forecast future saturation.

#### 3. Histogram
A multi-dimensional metric that samples observations (usually things like request durations or response sizes) and counts them in **configurable, cumulative buckets**. It also exposes a sum and total count of observations.
*   **Common examples:** `http_request_duration_seconds_bucket`, `grpc_server_handling_seconds_bucket`.
*   **Usage:** Histograms allow you to calculate quantiles (e.g., 90th, 99th percentiles) mathematically using the `histogram_quantile()` function. They are highly aggregatable across multiple pods.

#### 4. Summary
Similar to a histogram, a summary calculates configurable quantiles (e.g., 0.9, 0.99) over a sliding time window. It also exposes a sum and total count of observations.
*   **Difference from Histogram:** Quantiles in a summary are calculated **on the client-side** (inside the application code). Consequently, summaries **cannot be aggregated** across multiple instances of a service.
*   **Usage:** Use summaries when you need exact client-side quantiles and do not need to aggregate the metrics across multiple pods or nodes.

---

## 3. Prometheus Architecture Deep Dive

Prometheus is designed to be self-contained, highly reliable, and operationally simple. Unlike push-based metrics systems (e.g., InfluxDB, Datadog), Prometheus uses a **pull-based model** (scraping).

```
  ┌──────────────┐         Pull (Scrape)         ┌───────────────────┐
  │ Exporter/Pod │ <──────────────────────────── │ Prometheus Server │
  └──────────────┘                               └───────────────────┘
```

### The Pull vs. Push Trade-off

| Attribute | Pull (Prometheus Model) | Push (Traditional Model) |
|---|---|---|
| **Monitoring Overhead** | Prometheus controls the load and scrape rate. A target cannot overload the monitoring server. | If an application experiences a traffic spike, it pushes more metrics, potentially DDOSing the metrics server. |
| **Discovery** | Prometheus must locate targets dynamically using Service Discovery. | Targets must know the endpoint of the metrics server and authenticate. |
| **Debugging** | Any developer can query the `/metrics` endpoint of a pod using a simple `curl` command. | Difficult to inspect metrics locally without routing through the collector daemon. |
| **Short-lived workloads** | Requires a bridge like the **Pushgateway** because pods vanish before a scrape loop occurs. | Natively handled since the job pushes its metrics before exiting. |

### TSDB (Time Series Database) Storage Engine

The Prometheus TSDB is engineered to handle millions of samples per second on single nodes:
1.  **Head Block (Memory):** Incoming samples are appended to an active in-memory buffer called the *Head Block*.
2.  **Write-Ahead Log (WAL):** To prevent data loss if the pod restarts, every sample is written immediately to a sequential, append-only file on disk called the WAL. If Prometheus crashes, it replays the WAL on startup to restore the Head state.
3.  **2-Hour Compaction Blocks:** Every 2 hours, the Head Block's contents are flushed to a permanent directory on disk. This directory contains:
    *   `chunks/`: The raw metrics samples, compressed using Gorilla compression (which fits most floats into ~1.37 bytes).
    *   `index`: An index mapping metric names and label pairs to specific time-series IDs.
    *   `meta.json`: Metadata about time ranges and compaction generation.
4.  **Compaction:** A background thread merges older 2-hour blocks into larger 24-hour blocks to reduce index duplication and speed up queries over long time windows.

---

## 4. PromQL: Querying Time-Series Data

PromQL (Prometheus Query Language) is a declarative language designed specifically for querying multi-dimensional time-series data.

### Value Types in PromQL
*   **Instant Vector:** A set of time-series containing a single sample for each time series, all at the exact same timestamp.
    *   Example: `http_requests_total`
*   **Range Vector:** A set of time-series containing a range of data points over a historical time window.
    *   Example: `http_requests_total[5m]` (retrieves all data points recorded over the last 5 minutes). Note: Range vectors cannot be graphed directly; they must be fed into functions like `rate()` or `increase()`.
*   **Scalar:** A simple numeric floating-point value.
*   **String:** A simple literal string (rarely used, except in configuration).

### Essential PromQL Functions and Operators

#### `rate()`
Calculates the per-second average rate of increase of a counter over a time window. It automatically handles counter resets and counter gaps.
*   **Query:** `rate(http_requests_total[5m])`
*   **Rule of Thumb:** Always use `rate()` for counters in graphing. The window size (e.g., `[5m]`) should be at least 4 times the scrape interval to ensure accurate calculations.

#### `irate()`
Calculates the per-second instantaneous rate of increase of a counter based on the last two samples in the range vector.
*   **Query:** `irate(http_requests_total[5m])`
*   **Rule of Thumb:** Use `irate()` for volatile, highly dynamic graphs. Use `rate()` for alerting rules and trends, as `irate()`'s reliance on only two points makes it prone to spike noise.

#### `histogram_quantile()`
Calculates quantiles (percentiles) from a histogram's cumulative buckets.
*   **Query (p99 Latency):** `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))`
*   **Explanation:** Sums up the rate of increase of all latency buckets (`le` label), groupings them by service, and interpolates where the 99th percentile falls.

#### Aggregations: `sum`, `avg`, `min`, `max`, `by`, `without`
Aggregates vector results across label dimensions.
*   **Query:** `sum(rate(http_requests_total[5m])) by (kubernetes_namespace)`
*   **Explanation:** Sums HTTP rate metrics, grouping the outputs by namespace and discarding other labels (like pod IP, container name).

---

## 5. Kubernetes Service Discovery (SD)

In a Kubernetes cluster, IPs of pods and nodes are ephemeral. Prometheus solves this by querying the Kubernetes API Server to dynamically discover scrape targets.

Prometheus supports multiple **Kubernetes Service Discovery Roles**:
1.  **node:** Discovers worker nodes. Used to scrape Node Exporter and kubelet metrics.
2.  **pod:** Discovers all running pods. Used to scrape individual microservices.
3.  **service:** Discovers cluster services.
4.  **endpoints:** Discovers backing endpoint IPs of services. This is the most common role for scraping load-balanced applications.
5.  **ingress:** Discovers ingress resources.

### Relabel Configurations (`relabel_configs`)

Before Prometheus scrapes a target, it runs the target's metadata labels through a sequential pipeline of relabeling rules. This allows Prometheus to:
*   Filter out targets it shouldn't scrape.
*   Modify the metric path, port, or scheme.
*   Standardize labels (e.g., renaming `__meta_kubernetes_pod_name` to `pod`).

#### Example Relabeling Logic
```yaml
relabel_configs:
  # 1. Keep only pods containing the annotation "prometheus.io/scrape: true"
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: "true"
  
  # 2. Extract pod port from annotation and rewrite the __address__ label
  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
    action: replace
    target_label: __address__
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
```

---

## 6. Exporters: Metric Collection Layer

Not all systems expose Prometheus-formatted metrics natively. Exporters act as translators, querying system metrics and serving them as OpenMetrics plaintext.

In a healthy production Kubernetes cluster, SREs deploy a standard set of exporters:

```
                  ┌───────────────────────┐
                  │ kube-apiserver        │ ──┐
                  └───────────────────────┘   │
                  ┌───────────────────────┐   │
                  │ kube-state-metrics    │ ──┼─► [ Prometheus Scraper ]
                  └───────────────────────┘   │
                  ┌───────────────────────┐   │
                  │ cAdvisor (Kubelet)    │ ──┘
                  └───────────────────────┘
```

### 1. cAdvisor (Container Advisor)
cAdvisor is **embedded directly inside the Kubelet** daemon on every node.
*   **Purpose:** Exposes resource usage, memory limits, CPU cycles, and network interface throughput of *individual containers* running on the node.
*   **Key Metrics:**
    *   `container_cpu_usage_seconds_total`: Cumulative CPU time consumed by the container.
    *   `container_memory_working_set_bytes`: Active memory consumption (the metric the OOM Killer uses to terminate pods).
    *   `container_spec_cpu_quota`: The configured CPU limit in milliseconds.

### 2. kube-state-metrics (KSM)
A deployment that watches the API Server's internal state.
*   **Purpose:** Generates metrics about object configurations and object health (e.g., how many replicas are desired vs. running, resource requests, namespaces, node scheduling readiness). It does *not* monitor resource usage, but rather the cluster's *desired vs actual state*.
*   **Key Metrics:**
    *   `kube_pod_container_resource_limits`: The resource limits defined in pod manifests.
    *   `kube_deployment_status_replicas_unavailable`: Out-of-service pod counts in a deployment.
    *   `kube_node_status_condition`: Health status checks of physical host nodes.

### 3. Node Exporter
Deployed as a `DaemonSet` using host namespace mounting.
*   **Purpose:** Monitors the physical host virtual machine hardware (CPU load, physical RAM, disk write metrics, network interface throughput).
*   **Key Metrics:**
    *   `node_cpu_seconds_total`: Time spent in CPU states (user, system, idle, iowait).
    *   `node_memory_MemAvailable_bytes`: Available host system memory.
    *   `node_filesystem_free_bytes`: Available disk space.

---

## 7. Grafana: Visualization Layer

Grafana is an open-source analytics and visualization platform that connects to Prometheus to render graphs and dashboards.

### Dashboard Design Principles
1.  **Hierarchy (The SRE Hierarchy):**
    *   *Level 1:* High-level organizational SLOs (are customers experiencing errors? is latency high?).
    *   *Level 2:* Service components (databases, messaging queues, backend API targets).
    *   *Level 3:* Pod container internals (JVM GC time, CPU throttling, thread pools, file descriptors).
2.  **Minimize Visual Noise:** Avoid plotting 50 lines on a single graph. Use aggregation queries like `sum(...) by (service)` or filter dashboards using dynamic variables (e.g., selecting a single namespace).
3.  **Color Contextualization:** Use standardized color schemes (e.g., green for healthy, orange for warnings, blinking red for critical SLO breaches) so operators can diagnose problems instantly.

---

## 8. Alerting and Noise Reduction

Alerting is the critical bridge between observability metrics and human intervention. Unmanaged alerting leads to **alert fatigue**, a state where engineers ignore alarms because of frequent false positives.

### Alertmanager Lifecycle

```
  [ Prometheus Rule Engine ] ──(Pushes Firing Alerts)──► [ Alertmanager ]
                                                               │
     ┌─────────────────────── Grouping & Silences ─────────────┘
     ▼
  [ Receivers: Slack / PagerDuty / Webhook ]
```

1.  **Prometheus Rule Engine:** Periodically queries the TSDB (e.g., every 15 seconds). If a rule expression (e.g., `up == 0`) returns results, it marks the alert as `PENDING`. If the breach persists longer than the duration specified in the `for` clause (e.g., `for: 5m`), the state transitions to `FIRING`, and Prometheus pushes the alert payload to Alertmanager.
2.  **Alertmanager Processing:**
    *   **Deduplication:** Aggregates alerts with matching labels from multiple Prometheus instances.
    *   **Grouping:** Combines related alerts into a single notification context. For instance, if a network switch goes offline, Alertmanager groups 100 node-offline alerts into a single message, rather than sending 100 individual pages.
    *   **Inhibition:** Suppresses secondary alerts when a primary alert is firing. For example, if `NodeExporterOffline` is firing, suppress `ContainerCpuThrottling` notifications on that node, as the host is already known to be down.
    *   **Silencing:** Allows SREs to provision temporary silence windows for planned maintenance or ongoing incident mitigation.
    *   **Routing:** Directs alerts to receivers based on labels (e.g., routing `severity=critical` alerts to PagerDuty to page the on-call engineer, and routing `severity=warning` alerts to a Slack channel).
