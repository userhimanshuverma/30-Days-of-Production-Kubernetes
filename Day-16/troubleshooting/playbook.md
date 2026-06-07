# Day 16 Troubleshooting Playbook: Resolving Log Pipeline Failures

This runbook helps SREs diagnose and resolve issues in Kubernetes logging pipelines, covering Fluent Bit agents, Loki ingestion, and Elasticsearch storage backends.

---

## Scenario 1: Pod is Running but Logs are Missing in Loki/Elasticsearch

### Symptoms
`kubectl logs pod-name` shows application output, but searching in Grafana/Kibana returns zero results for the namespace.

### Root Cause
1. **Config tag mismatch:** Fluent Bit's input tag does not match the filters or outputs.
2. **Kubelet path naming change:** The Kubernetes container runtime path structure changed, causing the Fluent Bit tail path to miss files.
3. **RBAC permission error:** Fluent Bit does not have permissions to read pod metadata from the API server, causing the K8s filter to drop entries.

### Investigation
1. Check Fluent Bit agent error logs:
   ```bash
   kubectl logs -n logging daemonset/fluent-bit --tail=100 | grep -iE "error|warning|fail"
   ```
2. Verify Fluent Bit has read access to node host logs:
   ```bash
   kubectl exec -n logging daemonset/fluent-bit -- ls -l /var/log/containers/
   ```
3. Test connectivity to the database:
   ```bash
   kubectl exec -n logging daemonset/fluent-bit -- nc -zv loki.logging.svc 3100
   ```

### Resolution
* **If path mismatch:** Update `/var/log/containers/*.log` path in `fluent-bit-config` input configuration.
* **If RBAC error:** Apply correct ClusterRole bindings. Verify the ServiceAccount has access to read `namespaces` and `pods` resources:
   ```bash
   kubectl auth can-i get pods --as=system:serviceaccount:logging:fluent-bit
   ```

### Prevention
Implement automated liveness probes checking Fluent Bit output connections. Set up alerts on upstream data loss metrics.

---

## Scenario 2: Fluent Bit Crashes with OOMKilled Under High Traffic

### Symptoms
The Fluent Bit pod restarts frequently, showing `OOMKilled` status:
```bash
kubectl get pods -n logging -l k8s-app=fluent-bit
# Status: CrashLoopBackOff, Last State: Terminated (Reason: OOMKilled)
```

### Root Cause
Downstream database latency causes logs to accumulate in Fluent Bit's memory buffer queue, exceeding pod RAM resource limits.

### Investigation
Check memory consumption metrics of the DaemonSet:
```bash
kubectl top pod -n logging -l k8s-app=fluent-bit
```
Inspect stats using Fluent Bit's local HTTP API:
```bash
kubectl port-forward -n logging fluent-bit-xxxx 2020:2020
curl http://localhost:2020/v1/storage
```
Look at the `mem_limit` vs total logs pending.

### Resolution
1. Set input limits (`Mem_Buf_Limit`) in the ConfigMap to pause tailing when memory buffers are full:
   ```ini
   [INPUT]
       Name          tail
       Path          /var/log/containers/*.log
       Mem_Buf_Limit 5MB
   ```
2. Adjust container memory limits in the DaemonSet manifest to at least `256Mi`.

### Prevention
Always enable filesystem buffering (`storage.type filesystem`) so logs are written to node disk if downstreams slow down.

---

## Scenario 3: Loki Ingest Limits (429 Too Many Requests)

### Symptoms
Fluent Bit logs display HTTP status code `429` warnings from Loki:
```text
[2026/06/07 12:00:00] [warn] [output:loki:loki.0] HTTP status=429, body="entry too far behind, or rate limit exceeded"
```

### Root Cause
The application pod is emitting logs faster than Loki's default tenant ingestion limit (typically 4MB/s per stream).

### Investigation
Identify which app pod is spamming logs:
```bash
kubectl logs -n logging statefulset/loki | grep -i "rate limit"
```
Or check stdout volume sizes on the nodes:
```bash
du -sh /var/log/pods/*
```

### Resolution
1. Increase stream limits in Loki's `limits_config` settings:
   ```yaml
   limits_config:
     ingestion_rate_mb: 15
     ingestion_burst_size_mb: 25
   ```
2. Apply Fluent Bit filters to drop debug logs or noisy healthchecks to reduce volume before shipping.

### Prevention
Configure rate-limiting alerts to flag application pods emitting abnormally high log volume (e.g. infinite loops).

---

## Scenario 4: Elasticsearch Unassigned Shards and Red Cluster Health

### Symptoms
Elasticsearch cluster status is `red`. Logging slows down or Kibana displays: *"No index patterns found"* or writes fail.

### Root Cause
Elasticsearch has unassigned primary shards, usually caused by disk exhaustion on storage nodes.

### Investigation
1. Query Elasticsearch cluster health API:
   ```bash
   curl http://elasticsearch.logging.svc:9200/_cluster/health?pretty
   ```
2. Identify why shards are unassigned:
   ```bash
   curl http://elasticsearch.logging.svc:9200/_cat/shards?v&h=index,shard,state,unassigned.reason | grep UNASSIGNED
   ```
   *Common reason:* `ALLOCATION_FAILED` (Disk watermark exceeded).

### Resolution
1. Delete old indexes to free up disk space:
   ```bash
   curl -XDELETE http://elasticsearch.logging.svc:9200/k8s-logs-2026.05.*
   ```
2. Reset allocator blocks after freeing space:
   ```bash
   curl -XPUT http://elasticsearch.logging.svc:9200/_settings -H 'Content-Type: application/json' -d'
   {"index.blocks.read_only_allow_delete": null}'
   ```

### Prevention
Implement Elasticsearch Index Lifecycle Management (ILM) policies to delete indices automatically before disk usage reaches 85% watermarks.

---

## Scenario 5: Stack Traces are Fragmented into Multiple Log Lines

### Symptoms
When looking at Java, Python, or Go exceptions in Grafana/Kibana, each line of the stack trace appears as a separate log entry.

### Root Cause
Fluent Bit treats every line written to the container log file as an independent event.

### Investigation
Inspect raw CRI files on the host:
```bash
# Multi-line trace prints as separate lines in CRI logs
cat /var/log/containers/myapp-xxx.log
```

### Resolution
Configure a `multiline-parser` filter in Fluent Bit:
```ini
[FILTER]
    Name                  multiline
    Match                 kube.*
    Multiline.key_content log
    Multiline.parser      multiline-java
```

### Prevention
Standardize on JSON structured logging in application code. JSON logs package complete stack traces inside a single JSON string attribute, avoiding multiline parser complexity.
