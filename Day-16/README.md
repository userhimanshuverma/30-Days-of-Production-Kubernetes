# 📖 Day 16 - Logging in Kubernetes
### 🏷️ PHASE 3 — OBSERVABILITY & PRODUCTION OPERATIONS

Welcome to Day 16 of **30 Days of Production Kubernetes**. Today, we address the lifeline of cluster diagnostics and incident response: **Centralized Logging**.

In a production Kubernetes environment, container instances are ephemeral, scheduling is dynamic, and applications are distributed across hundreds of CPU cores. When a container crashes, its local files—including its standard output logs—are discarded by the host container engine. Without a robust centralized logging pipeline, troubleshooting a production failure becomes impossible. SREs and platform engineers must design log pipelines that capture, process, ship, index, and store terabytes of log data efficiently and securely.

---

## 🗺️ Day 16 Directory Structure

Here is how today's learning resources are organized:
- [notes/logging-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/notes/logging-deep-dive.md) — Architectural details, comparing Loki vs Elasticsearch indexing engines, Fluent Bit pipelines, and parser designs.
- [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-16/diagrams/) — 12 dedicated Mermaid diagrams mapping everything from Fluent Bit input engines to Loki chunk layouts.
- [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-16/manifests/) — Complete, annotated manifests for deploying Fluent Bit (DaemonSet & ConfigMap), Loki, and Elasticsearch with Kibana.
- [labs/](file:///d:/30_Days_of_Production_Kubernetes/Day-16/labs/) — Step-by-step hands-on SRE labs:
  - [Lab 1: Configure & Deploy Fluent Bit DaemonSets](file:///d:/30_Days_of_Production_Kubernetes/Day-16/labs/lab-1-fluent-bit-daemonset.md)
  - [Lab 2: Deploy Loki & Query Logs using Grafana LogQL](file:///d:/30_Days_of_Production_Kubernetes/Day-16/labs/lab-2-loki-grafana-stack.md)
  - [Lab 3: Spin up the EFK (Elasticsearch/Kibana) Logging Pipeline](file:///d:/30_Days_of_Production_Kubernetes/Day-16/labs/lab-3-efk-elasticsearch-kibana.md)
- [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/production-notes/lessons-learned.md) — Operational guidance on logging costs, ingestion backpressure, PII masking, index rollover, and audit compliance.
- [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/troubleshooting/playbook.md) — Playbooks for missing pod logs, OOM-killed logging daemons, slow Loki queries, and Elasticsearch mapping conflicts.
- [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/exercises/challenges.md) — Challenge exercises to configure PII masking rules and write advanced LogQL metrics.
- [resources/log-explorer.html](file:///d:/30_Days_of_Production_Kubernetes/Day-16/resources/log-explorer.html) — Futuristic, interactive, single-page HTML simulator dashboard.
- [resources/reference-links.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/resources/reference-links.md) — Reference materials, Fluent Bit documentation, and incident runbooks.

---

## 1. Why Logging Matters in Kubernetes

In traditional environments, logs lived on local VMs in directories like `/var/log/nginx/access.log`. Developers SSH'd into nodes and ran `tail -f` or `grep` commands.

In Kubernetes, this debugging model is completely broken. If you run:
```bash
kubectl logs my-api-pod-xyz -n production
```
You are querying the container engine (containerd/CRI-O) running on the specific node where that pod lives. If the pod crashes, is evicted by the scheduler, or the node scales down, **those logs are gone forever**. 

Logs are critical for:
* **Incident Response:** Diagnosing OOMKills, database connection timeouts, and application errors.
* **Security Auditing:** Tracking API calls, token requests, and unauthorized execution.
* **Business intelligence & Analytics:** Measuring traffic volume, error rates, and API performance.

---

## 2. Kubernetes Logging Challenges

Workload architectures in Kubernetes create unique challenges for log management:

* **Ephemeral Pods:** Pods can be destroyed or rescheduled at any second. If logs are stored inside the container filesystem, they vanish.
* **Distributed Workloads:** A single logical service might run as 20 replica pods across 5 physical nodes. Checking logs manually for each replica is impossible.
* **Multi-Node Host Path Environments:** Standard output logs are written by the container runtime to `/var/log/pods/` on the physical node. Manually extracting logs requires node-level SSH access, which is blocked in secure production environments.
* **Multi-Line Stack Traces:** Languages like Java, Go, and Python print error trace messages across dozens of lines. Without aggregation and proper parsing, a single crash dump gets split into individual, disconnected log entries, making troubleshooting extremely difficult.

---

## 3. Centralized Logging Architecture

To solve these challenges, we implement a **Centralized Logging Pipeline**. The workflow separates logging into five distinct stages:

```
┌─────────────────┐       ┌────────────┐       ┌─────────────┐       ┌───────────┐       ┌──────────────┐
│ Application Log │ ────► │ Collection │ ────► │ Aggregation │ ────► │  Storage  │ ────► │Visualization │
│   (pod stdout)  │       │ (DaemonSet)│       │  (Ingester) │       │(DB Engine)│       │ (Dashboard)  │
└─────────────────┘       └────────────┘       └─────────────┘       └───────────┘       └──────────────┘
```

1. **Application Logs:** Pod processes write JSON or structured logs straight to standard output (`stdout`) and standard error (`stderr`) streams.
2. **Collection (Collector):** A logging daemon (like Fluent Bit or Fluentd) runs as a `DaemonSet` on every node, tailing the local container log files.
3. **Aggregation / Processing:** The collector parses the raw string streams, enriches them with Kubernetes metadata (Pod name, namespace, labels, node IP), filters out noisy lines, and masks sensitive data.
4. **Storage:** The processed logs are forwarded to a scalable, persistent storage database (like Loki or Elasticsearch).
5. **Visualization:** SREs query and explore the log streams using graphical dashboards (Grafana or Kibana).

---

## 4. Fluent Bit Deep Dive

**Fluent Bit** is a lightweight, high-performance log processor and forwarder written in C. It uses minimal CPU and memory compared to its older brother, Fluentd.

Its engine operates as a pipeline of four key components:

```
[ INPUT ] ──► [ PARSER ] ──► [ FILTER ] ──► [ OUTPUT ]
```

* **Inputs:** Specifies where Fluent Bit collects logs. The most common input is `tail`, which points to the local node path `/var/log/containers/*.log`.
* **Parsers:** Converts raw unstructured logs (like a plain Apache access text line or standard application stack traces) into structured JSON formats.
* **Filters:** Modifies or enriches the log entries. The `kubernetes` filter talks to the local Kubelet API to inject pod names, namespaces, container names, and pod labels. The `grep` filter discards logs matching specific regex rules.
* **Outputs:** Defines where Fluent Bit sends the clean logs. It can route streams to Loki, Elasticsearch, Kafka, or cloud storage buckets.

---

## 5. Loki Deep Dive: The Label-Based Approach

**Grafana Loki** is a horizontally scalable, highly available log aggregation system inspired by Prometheus. It is designed to be very cost-effective.

```
       Incoming Logs ──► [ Loki Ingester ]
                                │
          ┌─────────────────────┴─────────────────────┐
          ▼                                           ▼
[ Metadata Index ]                              [ Log Chunks ]
  (Labels only)                                 (Compressed)
  Stored in fast DB                             Stored in Object Storage
  (e.g., BoltDB/Loki DB)                        (e.g., S3, MinIO, GCS)
```

Unlike Elasticsearch, which parses and full-text indexes every single word in every log line, Loki **only indexes the metadata labels** (like `app=payment`, `namespace=production`, and `node=node-1`). 
* **Storage Model:** Loki compresses the raw log lines into chunks and stores them in cheap object storage (like AWS S3 or MinIO). The index database remains tiny, saving huge amounts of money on RAM and disk costs.
* **Querying Logs:** Loki uses **LogQL** (similar to PromQL). Because Loki does not build a full-text index, searching a huge timeframe requires Loki queriers to scan the raw chunks in parallel. This trade-off makes ingestion cheap and fast, but raw text searches can be slower than Elasticsearch.

---

## 6. The EFK Stack: Full-Text Search

The **EFK Stack** (Elasticsearch, Fluent Bit/Fluentd, Kibana) is a classic enterprise logging pattern.

```
Incoming logs ────► [ Fluent Bit ] ────► [ Elasticsearch ] ◄──── [ Kibana UI ]
                                               │
                                      ┌────────┴────────┐
                                      ▼                 ▼
                              [ Full-Text Index ]   [ Raw Logs ]
                              (Indexed fields)      (Stored in Shards)
```

* **Elasticsearch:** A distributed, JSON-based search engine. It creates inverted indexes for every token inside the logs. This enables near-instant searches across millions of records.
* **Fluent Bit / Fluentd:** Acts as the shipper, transforming container stdout streams and writing directly to Elasticsearch REST indices.
* **Kibana:** The frontend visualization dashboard, providing deep search capabilities, live tail monitoring, and complex data visualizations.
* **The Trade-Off:** EFK provides ultra-fast search times but is extremely hungry for CPU, memory (RAM), and expensive persistent block storage.

---

## 7. Production Logging Strategies

Operating logging at scale requires architectural discipline:

* **Structured Logging:** Force all internal applications to log in **JSON format** (e.g. `{"timestamp": "...", "level": "info", "message": "Login success", "user_id": 491}`). This makes parsing trivial, avoids regex overhead, and guarantees consistent database indexing.
* **Correlation / Trace IDs:** Inject a unique UUID header (like `X-Correlation-ID`) at the API Gateway level. Pass this header down through every downstream microservice call. Log this ID in every log entry. This allows SREs to query for a specific ID and see the entire request lifecycle across all microservices:
  ```
  Gateway (Trace: 4f12) ──► Auth Service (Trace: 4f12) ──► Payment Service (Trace: 4f12)
  ```
* **Log Retention Tiers:** Do not keep raw debug logs forever. Set retention rules (e.g. 7 days for DEBUG, 30 days for INFO, 90 days for WARN/ERROR) and offload old logs to cheap cold storage buckets (e.g. Glacier) before deleting.
* **Cost Optimization:** Drop verbose healthcheck access logs (e.g., `/healthz` or `/metrics`) at the Fluent Bit level. Mask PII data (like Credit Cards or social security numbers) before shipping to reduce compliance overhead and DB size.

---

## 🏁 Summary of Daily Tasks

To complete Day 16, proceed with the following steps:
1. **Explore Architecture Diagrams:** View the pipeline visual mappings in the [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-16/diagrams/) folder.
2. **Read Conceptual Notes:** Review [notes/logging-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/notes/logging-deep-dive.md) for comparing Loki and Elasticsearch, Fluent Bit configurations, and LogQL basics.
3. **Interactive Simulation:** Run the interactive [Kubernetes Log Explorer Simulator](file:///d:/30_Days_of_Production_Kubernetes/Day-16/resources/log-explorer.html) in your browser to experience request tracing, log routing, PII masking, and incident analysis.
4. **Execute Hands-on Labs:**
   * Run [Lab 1: Configure & Deploy Fluent Bit DaemonSets](file:///d:/30_Days_of_Production_Kubernetes/Day-16/labs/lab-1-fluent-bit-daemonset.md) to inspect local CRI logs.
   * Run [Lab 2: Deploy Loki & Query Logs using Grafana LogQL](file:///d:/30_Days_of_Production_Kubernetes/Day-16/labs/lab-2-loki-grafana-stack.md) to set up Loki and explore labels.
   * Run [Lab 3: Spin up the EFK Logging Pipeline](file:///d:/30_Days_of_Production_Kubernetes/Day-16/labs/lab-3-efk-elasticsearch-kibana.md) to query logs with Kibana and manage indexes.
5. **Study Production Hardening Guidelines:** Read [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/production-notes/lessons-learned.md) to optimize indices, write masking rules, and implement retention policies.
6. **Review Troubleshooting Runbook:** Study [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/troubleshooting/playbook.md) to identify ingestion bottlenecks, backpressure warnings, and missing logs.
7. **Solve Daily Challenges:** Complete the pipeline filter configuration and LogQL tasks in [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/exercises/challenges.md).
