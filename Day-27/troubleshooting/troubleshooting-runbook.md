# Troubleshooting Runbook: Running Data Platforms on Kubernetes

This document provides step-by-step diagnostic workflows and resolutions for common failures encountered when operating Spark, Airflow, Kafka, and Pinot on Kubernetes.

---

## Incident 1: Spark Executor Pods Failing (OOMKilled)

### Symptoms
* Spark jobs fail with exit code `137` (OOMKilled).
* The driver logs output: `Lost executor x on host y: Container killed by YARN/Kubernetes for exceeding memory limits.`

### Root Cause
Spark executors run in a JVM container. By default, JVM heap memory configurations do not account for off-heap allocations, PySpark execution processes, or native memory used during operations like compression. When the total memory exceeds the container's cgroup limits, the Kubernetes kernel kills the pod immediately.

### Investigation
1. Run `kubectl get pods -l role=spark-executor` to identify failed pods.
2. Inspect the pod description:
   ```bash
   kubectl describe pod <failed-executor-pod>
   ```
   Look for the `Last State` field:
   ```
   State:          Failed
     Reason:       OOMKilled
     Exit Code:    137
   ```
3. Check driver logs for memory metrics before the crash:
   ```bash
   kubectl logs <driver-pod-name> | grep -i "MemoryOverhead"
   ```

### Resolution
Increase the Spark memory overhead ratio. In your `SparkApplication` manifest, increase `spark.executor.memoryOverhead` (default is 10% of executor memory, which is often insufficient for heavy Python/PySpark workloads):
```yaml
sparkConf:
  "spark.executor.memory": "4g"
  "spark.executor.memoryOverhead": "2g" # Increase overhead to 50%
```

### Prevention
* Implement node-level node-problem-detector alerts to flag memory exhaustion before pods are terminated.
* Set resource requests equal to limits for Spark driver pods to ensure they are scheduled in the `Guaranteed` QoS class.

---

## Incident 2: Airflow Scheduler Latency & Task Lag

### Symptoms
* Airflow DAG execution states remain in `scheduled` or `queued` for several minutes.
* Airflow web server reports: `The scheduler does not appear to be running.`

### Root Cause
1. **Postgres Connection Pool Saturation**: The Airflow Scheduler opens multiple database connections. If Postgres hits its max connection limit, queries block.
2. **Kubernetes API Throttling**: The scheduler calls the K8s API server to launch worker pods. If rate-limits are hit, pod creations are delayed.

### Investigation
1. Check scheduler logs for database connection errors:
   ```bash
   kubectl logs deployment/airflow-scheduler -c scheduler | grep -E -i "connection|pool"
   ```
2. Verify the number of active database connections:
   ```bash
   kubectl exec -it statefulset/airflow-postgres -- psql -U airflow -d airflow -c "SELECT count(*) FROM pg_stat_activity;"
   ```
3. Inspect K8s API server events to check if API rate-limiting is occurring:
   ```bash
   kubectl get events --sort-by='.metadata.creationTimestamp' -n default | grep -i "TooManyRequests"
   ```

### Resolution
1. **Optimize Database Pool Sizing**: Adjust pool configurations in the Airflow ConfigMap:
   ```ini
   AIRFLOW__CORE__SQL_ALCHEMY_POOL_SIZE=30
   AIRFLOW__CORE__SQL_ALCHEMY_MAX_OVERFLOW=15
   ```
2. **Enable Pgbouncer**: Implement a database proxy like PgBouncer in front of PostgreSQL to reuse connections.

### Prevention
* Monitor Postgres CPU and active connections.
* Implement database auto-vaccuming on Airflow metadata tables to prevent database bloat.

---

## Incident 3: Kafka Broker Restart Loops

### Symptoms
* Kafka broker pods enter `CrashLoopBackOff` during rolling upgrades.
* Headless discovery fails; producers report connection resets.

### Root Cause
1. **Dirty Disk Unmounts**: When a broker restarts abruptly, its active index files can corrupt. During startup, the broker performs an index rebuild which can take a long time. If the liveness probe fires during this time, Kubernetes restarts the pod again, creating an infinite reboot loop.
2. **ZooKeeper Session Timeout**: The broker GC pause or startup delay exceeds the ZooKeeper session timeout, causing Zookeeper to assume the broker is offline.

### Investigation
1. Inspect broker container logs:
   ```bash
   kubectl logs statefulset/production-kafka-kafka-0
   ```
   Look for log lines showing:
   ```
   Loading segments...
   Fatal error during KafkaServer startup.
   ```
2. Check if the broker is crashing because of liveness probe timeouts:
   ```bash
   kubectl describe pod production-kafka-kafka-0 | grep -A 3 -i "Liveness"
   ```

### Resolution
1. **Extend Startup and Liveness Probes**: Increase the `initialDelaySeconds` and `periodSeconds` of the probes in the Kafka spec to allow index recovery to finish:
   ```yaml
   livenessProbe:
     initialDelaySeconds: 60
     periodSeconds: 15
     failureThreshold: 8
   ```
2. **Corrupted Index Remediation**: If an index is corrupt, delete the matching `.index` file from the PVC mount. Kafka will rebuild the index on startup.

### Prevention
* Set `terminationGracePeriodSeconds: 300` in the Kafka StatefulSet to allow the broker to flush memory buffers to disk before shutting down.
* Use Strimzi's automated reconciliation loops to handle restarts sequentially.

---

## Incident 4: Pinot Ingestion Delays & Segment Lag

### Symptoms
* Queries for real-time events return stale data.
* Pinot Controller dashboard reports increasing Kafka partition offset lag for consumer tables.

### Root Cause
* **Segment Memory Allocation Exhaustion**: Pinot Server pods run out of off-heap memory, preventing them from flushing segments to deep storage.
* **GC Pauses**: Long GC sweeps pause the real-time consumer thread, causing it to fall behind Kafka's ingress rate.

### Investigation
1. Run a query using the Pinot Controller API to inspect table status:
   ```bash
   kubectl exec -it deployment/pinot-controller -- curl -s http://localhost:9000/tables/userClicks/state
   ```
2. Fetch consumer partition lag metrics:
   ```bash
   # Execute inside a broker or SRE pod with kcat installed
   kcat -b production-kafka-kafka-bootstrap:9092 -G production-analytics-consumers user-clicks
   ```
3. Inspect memory usage of Pinot Server pods:
   ```bash
   kubectl top pods -l app=pinot-server
   ```

### Resolution
1. **Allocate Sufficient Off-Heap Memory**: Pinot maps segments to memory using MMAP, which requires large JVM direct/off-heap allocations. Update Pinot Server JVM options:
   ```ini
   PINOT_SERVER_JVM_OPTS="-Xms4g -Xmx4g -XX:MaxDirectMemorySize=12g"
   ```
2. **Increase Partition Count**: If a single partition ingest rate is saturated, increase the Kafka partition count and matching Pinot consumer replicas.

### Prevention
* Implement Prometheus rules alerting when `pinot_server_realtimeIngestionLag` exceeds `60000ms`.
* Automatically scale Pinot Server replicas using HPAs when segment counts increase.

---

## Incident 5: Storage Provisioning Timeouts & Disk Saturation

### Symptoms
* Pods remain in `Pending` state with volume errors.
* Database operations fail with `Read-only file system` or `No space left on device` logs.

### Root Cause
1. **Dynamic Provisioning Failure**: The Cloud Controller Manager cannot attach the requested volume because of Availability Zone mismatch or AWS volume limits.
2. **I/O Saturation**: High disk write load saturates the volume's IOPS quota, causing disk writes to hang, which triggers container liveness probe failures.

### Investigation
1. Check scheduling errors on the pending pod:
   ```bash
   kubectl describe pod <pending-pod>
   ```
   Look for events like:
   ```
   Warning  FailedAttachVolume  5m  attachdetach-controller  AttachVolume.Attach failed : volume "...": Volume is in use by another node
   ```
2. Check volume disk space:
   ```bash
   kubectl exec -it <pod-name> -- df -h
   ```
3. Check volume IOPS usage:
   Use cloud provider monitoring (e.g., CloudWatch metrics for EBS volumes) or run `iotop` inside the worker node.

### Resolution
1. **Volume Expansion**: If disks are full, scale the PVC request size. K8s supports online volume expansion for compatible CSI drivers:
   ```bash
   kubectl edit pvc <pvc-name>
   # Increase storage: 50Gi to 100Gi, save and exit.
   ```
2. **AZ Alignment**: Verify that the node selector on the pod matches the Availability Zone of the persistent volume.

### Prevention
* Use `volumeBindingMode: WaitForFirstConsumer` on all storage classes to prevent AZ mismatch scheduling locks.
* Set up disk space alerts at 80% usage.
