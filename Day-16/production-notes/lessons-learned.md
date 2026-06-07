# Production Logging Lessons Learned: Observability at Scale

Operating centralized logging systems handling terabytes of log data per day exposes several operational bottlenecks. This note details SRE-tested design patterns, configurations, and lessons learned from operating observability pipelines at scale.

---

## 1. The Real Cost of Logging (Loki vs. Elasticsearch)

A common mistake is designing logging systems for worst-case requirements without analyzing ongoing storage costs.

### Cost Arithmetic Example:
Imagine a cluster generating **1 TB of raw logs per day**.
* **Elasticsearch (Full-Text Indexing):** 
  * The inverted index multiplies the storage requirement by ~1.3x to 1.5x (including replicas).
  * 1 TB of logs requires **1.5 TB of high-performance SSD block storage** (e.g., AWS EBS gp3) per day.
  * *Cost:* ~$120 per day (block storage) + high RAM JVM workloads on data nodes.
* **Grafana Loki (Label-Only Indexing):**
  * Logs are compressed (typically 5:1 ratio using Snappy/Gzip).
  * 1 TB of raw logs is compressed to **200 GB of object storage** (e.g., AWS S3).
  * *Cost:* ~$5 per day (S3 storage) + minimal CPU/RAM write path overhead.

> [!TIP]
> Use Loki for developer stdout streams and application debug logs. Reserve Elasticsearch for audit trails, security events, or business transactions where near-instant full-text search is required.

---

## 2. Mitigation of Agent Resource Overload & Backpressure

When downstream log databases (like Loki/ES) go offline or become slow, logging collectors (like Fluent Bit) continue reading files from disk.
* **The Hazard:** Fluent Bit loads log lines into memory to buffer them. If it has no limit on RAM usage, it will grow until the Linux kernel kills it due to out-of-memory (OOM) limits, causing log collection to stop completely.
* **The Fix:**
  1. Configure `Mem_Buf_Limit` on inputs. When the buffer limit is reached, Fluent Bit pauses log ingestion for that input file, leaving logs buffered in the local file system on the node until the output buffer drains.
  2. Map storage buffers to disk filesystem storage. This writes transient log chunks to node disk rather than keeping them in RAM.

```ini
[INPUT]
    Name          tail
    Path          /var/log/containers/*.log
    Mem_Buf_Limit 10MB
    Storage.type  filesystem
```

---

## 3. Sensitive Data Masking (PCI-DSS & HIPAA Compliance)

Storing Personal Identifiable Information (PII) like credit cards, passwords, or bearer tokens in raw logs violates compliance frameworks (like PCI-DSS or HIPAA).

### Fluent Bit Regex Masking Filter
We configure regex filters in Fluent Bit to scrub values matching patterns before they are sent over the network:

```ini
[FILTER]
    Name          rewrite_tag
    Match         kube.*
    Rule          $log "(?i)(password|token|bearer|secret)\s*[:=]\s*\"?[^\s\"]+\"?" k8s.sensitive $1 false

[FILTER]
    Name          modify
    Match         k8s.sensitive
    # Replace the matching string segment with [MASKED]
    Condition     Key_Value_Matches log (?i)(password|token|bearer|secret)\s*[:=]\s*\"?[^\s\"]+\"?
    # Strip or replace matches
```

> [!WARNING]
> Do not rely on application developers to write clean logs. Always enforce data masking at the infrastructure collector level to ensure PII is scrubbed before leaving the node.

---

## 4. Loki High Cardinality Labels Hazard

A common Loki anti-pattern is assigning dynamic values (like `client_ip`, `user_id`, `email`, or `trace_id`) as Loki labels.

* **Why it's bad:** Loki groups log lines into unique index streams for each combination of labels. If you create a label for `user_id` with 1,000,000 users, Loki will create 1,000,000 stream index directories.
* **The Symptom:** This degrades chunk generation, leading to thousands of tiny 5KB files in object storage, high memory usage on ingesters, and slow query lookups.
* **Correct Practice:** Only use low-cardinality static labels (e.g. `env`, `namespace`, `app`, `container`, `version`). Dynamic fields should be kept as text attributes in JSON log payloads and filtered at query time using LogQL parser filters (e.g. `| json | user_id = "102"`).

---

## 5. Production Logging Anti-Patterns

1. **Stdout/Stderr Bypassing:** Designing containers to write logs directly to local host folders (e.g. `/var/log/app.log`) inside the container file system. This breaks `kubectl logs` integration and bypasses node-level log rotation, eventually filling up the node disk.
2. **Missing Node Log Rotation:** Failing to set log limits in container runtime configurations (e.g. `containerd` or `docker`). By default, containerd logs grow forever unless rotated by a host tool (like `logrotate`).
3. **No JVM Heap Limits on Elasticsearch:** Running Elasticsearch without setting explicit environment memory limits (`ES_JAVA_OPTS="-Xms8g -Xmx8g"`). Elasticsearch will consume all available node RAM, causing the Kubernetes scheduler to evict other application pods.
4. **Failing to set Resource Limits on Collectors:** Running Fluent Bit DaemonSets without resource limits. A log injection attack on an application pod can cause the local log collector to consume 100% of node CPU resources, choking actual application processes.
