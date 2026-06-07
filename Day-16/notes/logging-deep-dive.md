# Logging in Kubernetes — Deep-Dive Reference Notes

To design a scalable, low-latency, and cost-efficient logging architecture, SREs must understand how containers emit logs, how local container runtimes buffer them on disk, and how shippers extract, process, and index them. This note provides a comprehensive technical reference.

---

## 1. How Container Logging Works Under the Hood

In Linux, a process writes standard output (`stdout`) and standard error (`stderr`) to file descriptor 1 and file descriptor 2. 

When a container runs inside Kubernetes, the container runtime (e.g., `containerd` or `CRI-O`) intercepts these streams and redirects them to a local JSON or log file on the host's filesystem.

```
┌───────────────────────────────── Node Host File System ───────────────────────────────────┐
│                                                                                           │
│  ┌───────────────────────┐                                                                │
│  │     Pod Container     │                                                                │
│  │  Writes stdout/stderr │                                                                │
│  └──────────┬────────────┘                                                                │
│             │ CRI Intercept                                                               │
│             ▼                                                                             │
│  ┌───────────────────────┐                                                                │
│  │   Container Runtime   │                                                                │
│  │   (containerd/CRI-O)  │                                                                │
│  └──────────┬────────────┘                                                                │
│             │                                                                             │
│             ▼ Writes log lines                                                            │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  Path: /var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container-name>/<retry>.log  │  │
│  └──────────────────────────────────────────┬──────────────────────────────────────────┘  │
│                                             │ Symlinked to                                │
│                                             ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  Path: /var/log/containers/<pod-name>_<namespace>_<container-name>-<container-id>.log │  │
│  └─────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                           │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

### The CRI Log Line Format
Unlike the old Docker JSON-file log driver, which wrapped logs in a JSON structure, the **Container Runtime Interface (CRI)** uses a high-performance space-delimited text format:

```text
2026-06-07T17:35:09.123456789Z stdout F {"level":"info","msg":"User login success","user_id":512}
```

A CRI log line is composed of four fields:
1. **Timestamp:** High-precision RFC3339 nano timestamp (e.g. `2026-06-07T17:35:09.123456789Z`).
2. **Stream Source:** Either `stdout` or `stderr`.
3. **Log Tag:** 
   * `F` (Full): Indicates this is a complete, single-line log entry.
   * `P` (Partial): Indicates that the log line was longer than the CRI buffer limit (typically 16KB) and has been split. Subsequent lines will continue with `P` tags until a final `F` tag is printed.
4. **Log Content:** The raw string output from the container process.

---

## 2. Fluent Bit Pipeline & Component Configuration

Fluent Bit uses a highly modular structure. The pipeline consists of five key lifecycle phases:

```
[ INPUT ] ──► [ PARSER ] ──► [ FILTER ] ──► [ BUFFER ] ──► [ ROUTER ] ──► [ OUTPUT ]
```

### 1. INPUT
Defines how logs are gathered. The `tail` plugin uses inotify to watch container log files.
* **Path:** `/var/log/containers/*.log`
* **Parser:** Specifies a parser to clean the initial CRI wrappers (e.g. extracting the timestamp, stream, and raw message).
* **Mem_Buf_Limit:** Restricts the RAM buffer size per file (e.g., `5MB`). If Fluent Bit hits this limit because the downstream database is slow (backpressure), it stops tailing the file until the buffer clears, avoiding OOM kills.

### 2. PARSER
Decodes raw strings into structured JSON maps.
* **CRI Parser:** Isolates the CRI headers (`timestamp`, `stream`, `logtag`) from the core content message.
* **JSON Parser:** Parses the core message if it is written in JSON (e.g. extracting `level`, `message`, `service`).

### 3. FILTER
Enriches or drops records.
* **Kubernetes Filter:** Reads the log file's name (which contains the namespace, pod name, and container ID), queries the local Kubelet API, and appends metadata: pod labels, annotations, namespace names, and node IPs.
* **Modify Filter:** Used to rename keys, set static labels (e.g., cluster name), or mask sensitive PII fields.
* **Grep Filter:** Excludes lines matching regular expressions (e.g., discarding healthchecks: `Exclude log ^(?=.*\/healthz).*$`).

### 4. BUFFER
Ensures reliability. Fluent Bit can buffer logs in memory (`Mem_Buf_Limit`) or write chunks to the host disk (`storage.type filesystem`) so logs are not lost if the pod restarts.

### 5. OUTPUT
Routes logs to backends. Fluent Bit can define multiple outputs using `Tag` matching.
* **Elasticsearch Output:** Writes JSON records to index paths (e.g. `k8s-logs-prod-YYYY.MM.DD`).
* **Loki Output:** Ships logs as streams using metadata labels as routing keys.

---

## 3. Loki vs. Elasticsearch: Storage & Indexing Models

| Feature | Grafana Loki | Elasticsearch (EFK) |
|---|---|---|
| **Indexing Philosophy** | Indexes labels (metadata) only. Raw logs are unindexed. | Indexes every field and token inside the raw log message. |
| **Storage Engine** | Compresses raw logs into chunks. Stores in object stores (S3, MinIO, GCS). | Stores logs in Lucene segments inside shards on block storage (gp3, SSD). |
| **RAM Footprint** | Extremely low. Index is tiny. | High. Requires large JVM heaps to hold in-memory index structures. |
| **Write Performance** | Super fast. No indexing overhead. | High, but limited by index generation rate and shard counts. |
| **Full-Text Search** | Requires scanning raw log chunks in parallel (slow for giant queries). | Near-instant lookup of any word across terabytes of data. |
| **Cost** | Extremely cheap. (Uses object storage). | Expensive. (Requires high-performance block storage). |

### Loki Storage Chunk Layout
Loki groups log lines by **Streams** (unique combinations of labels). Logs within a stream are gathered, compressed into chunks (gzip or snappy), and flushed to object storage:

```
Stream: {app="api-gateway", env="prod"}
  ├── Line 1: [10:00:00] Ingress request...
  ├── Line 2: [10:00:01] Processing...
  └── Line 3: [10:00:02] Completed 200 OK...
        │
        ▼ (Compressed block)
   [ Gzipped Chunk ] ──► Uploaded to S3 (bucket: /loki/chunks/)
```

### Elasticsearch Inverted Index Sharding
Elasticsearch breaks down the JSON document into keys and tokenized words. It builds an **Inverted Index** mapping terms to Document IDs:

```
Document 1: {"msg": "Database timeout error"}
Document 2: {"msg": "Network error in api"}

Inverted Index Table:
┌───────────┬──────────────┐
│ Term      │ Document IDs │
├───────────┼──────────────┤
│ Database  │ Doc 1        │
│ timeout   │ Doc 1        │
│ error     │ Doc 1, Doc 2 │
│ Network   │ Doc 2        │
│ api       │ Doc 2        │
└───────────┴──────────────┘
```
This is why searching for "timeout" or "error" is instant, but requires massive RAM to maintain the index tables.

---

## 4. Query Language Comparison: LogQL vs. Lucene / KQL

SREs use different syntax to query logs depending on the backend.

### Querying Loki with LogQL
LogQL uses a label selector followed by filter pipes:

```logql
# Find errors in Nginx gateway logs that contain "502 Bad Gateway"
{app="nginx-ingress", namespace="ingress-nginx"} |= "502 Bad Gateway"

# Extract JSON field, filter by nested field, and calculate error rates over time
sum by (status) (rate({app="payment-api"} | json | status_code >= 500 [5m]))
```

### Querying Elasticsearch with KQL (Kibana Query Language)
KQL provides search bar filtering and structured field query:

```kql
# Simple text filter
kubernetes.labels.app: "nginx-ingress" AND "502 Bad Gateway"

# Structured status code filtering
kubernetes.labels.app: "payment-api" AND http.status_code >= 500
```

---

## 5. Solving Multi-Line Stack Trace Fragmentation

A major challenge in logging is the **multi-line stack trace** printed by compilers when exceptions occur:

```text
2026-06-07T12:00:00Z stderr F java.lang.NullPointerException
2026-06-07T12:00:00Z stderr F   at com.example.MyService.doWork(MyService.java:42)
2026-06-07T12:00:00Z stderr F   at com.example.MyService.main(MyService.java:10)
```

Without multiline configuration, Fluent Bit treats each line as a **separate log entry**. This scrambles the trace in the database, making it impossible to search.

### Solution: Fluent Bit Multiline Engines
We configure Fluent Bit's built-in multiline engine with regex state rules.
* **Regex Rule:** Match the starting line pattern (e.g., matching a date or starting word), and merge any subsequent lines that start with whitespace or tabs (`\s+`) into the original log's body.

```ini
[MULTILINE_PARSER]
    name          multiline-java
    type          regex
    flush_timeout 1000
    # Match lines starting with a timestamp, then look for stack traces starting with spaces or 'at'
    key_content   log
    rules_list    java_rules

[RULES:java_rules]
    # State | Pattern                                   | Next State
    # ──────|───────────────────────────────────────────|───────────
    rule      "start_state"   "/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/"  "stack_state"
    rule      "stack_state"   "/^\s+at /"                               "stack_state"
```
This merges all lines of the exception into a single, cohesive log document containing the complete traceback.
