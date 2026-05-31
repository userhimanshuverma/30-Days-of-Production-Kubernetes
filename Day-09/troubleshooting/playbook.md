# 🚨 Day 09 Troubleshooting Playbook — StatefulSets & Databases

This operations guide outlines diagnostic workflows, commands, and resolution patterns for 10 realistic database and StatefulSet failure modes on Kubernetes.

---

## 1. StatefulSet Pod Stuck in Terminating

### Symptoms
You trigger a deletion or downscale of a StatefulSet (e.g. `kubectl scale sts postgres --replicas=1`), and one of the pods is stuck indefinitely in the `Terminating` state.

### Root Cause
Kubernetes sends a `SIGTERM` to the container and waits for it to shut down cleanly. If the container process is blocked (e.g., waiting for an active transaction to commit, running a long database cleanup, or hung on a network disk mount that became unresponsive), the Pod remains terminating. Additionally, if the host node has failed and cannot confirm the pod's termination, the master control plane keeps the pod in `Terminating` to prevent a duplicate pod from mounting the same storage (violating the single-writer rule).

### Investigation
1. Inspect the Pod status and events:
   ```bash
   kubectl describe pod postgres-2
   ```
2. Check if the worker node hosting the pod is `NotReady`:
   ```bash
   kubectl get nodes
   ```
3. Check container logs to see what process is hung:
   ```bash
   kubectl logs postgres-2 --tail=100
   ```

### Resolution
* **If it's a hung node (Host Failure)**: **Never** force-delete a database pod without verifying the node status first. If you force-delete it while the node is still alive (but partitioned), the controller will start `postgres-2` on another node, resulting in two pods writing to the same disk simultaneously, causing catastrophic data corruption.
* **If the node is confirmed dead**: Delete the Pod and bypass the graceful deletion timeout:
   ```bash
   kubectl delete pod postgres-2 --grace-period=0 --force
   ```

### Prevention
Ensure your database application handles `SIGTERM` signals properly, aborting idle transactions and shutting down within the container's `terminationGracePeriodSeconds` (default: 30s; increase to 60s-120s for databases).

---

## 2. PVC Binding Failures (Pending Pods)

### Symptoms
StatefulSet pods are stuck in a `Pending` state.

### Root Cause
The PVC created by the `volumeClaimTemplates` block cannot bind to a `PersistentVolume`. This usually happens when the `StorageClass` is misconfigured, cloud quotas are exhausted, or there is an Availability Zone mismatch.

### Investigation
1. Get the list of PVCs:
   ```bash
   kubectl get pvc
   ```
   Look for PVCs in a `Pending` state (e.g., `pg-storage-postgres-1`).
2. Inspect the pending PVC's events:
   ```bash
   kubectl describe pvc pg-storage-postgres-1
   ```
   *Common message: `waiting for first consumer to be created before binding` (This is normal and means it is waiting for scheduling).*
3. Inspect the pending Pod's events:
   ```bash
   kubectl describe pod postgres-1
   ```
   *Common message: `0/3 nodes are available: 3 node(s) had volume node affinity conflict`.*

### Resolution
* **Volume Node Affinity Conflict**: This occurs when `VolumeBindingMode` is set to `Immediate`, causing the disk to be provisioned in Zone-A, but the scheduler places the Pod on a node in Zone-B. Delete the PVC and the StatefulSet, modify the `StorageClass` to use `volumeBindingMode: WaitForFirstConsumer`, and redeploy. This forces the disk to be created in the node's zone.
* **Quota/Configuration Issues**: Check if the CSI driver is running properly on your cluster:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
   ```

### Prevention
Always use `volumeBindingMode: WaitForFirstConsumer` for database block storage classes.

---

## 3. Replica Synchronization Issues (Postgres/Kafka)

### Symptoms
The cluster database runs, but replica pods are not receiving updates. In Kafka, the log is under-replicated. In Postgres, read queries to replicas return stale data.

### Root Cause
Network isolation, incorrect replication credentials, or resource starvation on the followers.

### Investigation
* **For PostgreSQL**:
  Connect to the leader database and query replication status:
  ```bash
  kubectl exec -it postgres-0 -- psql -U k8s_admin -d production_db -c "select * from pg_stat_replication;"
  ```
  If this returns empty, no replicas are connected.
* **For Kafka**:
  Check under-replicated partitions:
  ```bash
  kubectl exec -it kafka-0 -- kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-replicated-partitions
  ```

### Resolution
* Check the network routing path between pods:
  ```bash
  kubectl exec -it postgres-1 -- ping postgres-0.postgres-headless.default.svc.cluster.local
  ```
* Check replication credentials: Check if the Secret matches the replication credentials inside `postgresql.conf`.
* Check resource allocation: If the CPU usage of `postgres-1` is hitting its limits, scale the CPU requests/limits to prevent processing lags.

### Prevention
Establish Prometheus alerts on `pg_stat_replication` lag metrics and Kafka `UnderReplicatedPartitions` metrics.

---

## 4. Kafka Broker Failures & Unclean Elections

### Symptoms
Clients receive timeouts when producing or consuming from a Kafka topic. Running `kubectl get pods` shows a broker pod in `CrashLoopBackOff`.

### Root Cause
Broker crashed due to storage corruption or out-of-memory errors. If all replicas of a partition go offline, the broker might fail to elect a leader, stopping reads and writes.

### Investigation
1. Read the broker crash log:
   ```bash
   kubectl logs kafka-1 --previous
   ```
2. Describe the partition leader status:
   ```bash
   kubectl exec -it kafka-0 -- kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic my-production-topic
   ```
   Look for partitions where `Leader: -1`.

### Resolution
* If the broker is stuck on disk corruption (e.g. bad index files), you can force a rebuild by deleting the broker pod and its PVC. Kafka will rebuild the partition data from the other replica brokers.
* If a partition has no leader, you can trigger an **unclean leader election** as a last resort (accepting data loss to restore availability):
   ```bash
   kubectl exec -it kafka-0 -- kafka-leader-election.sh --bootstrap-server localhost:9092 --election-type UNCLEAN --topic my-production-topic --partition 0
   ```

### Prevention
Enforce `min.insync.replicas=2` and `replication.factor=3` to guarantee partition resilience.

---

## 5. PostgreSQL Failover / Split-Brain Recovery

### Symptoms
Two PostgreSQL pods are running as write-leaders, or no write-leader can be found, returning database write errors to client applications.

### Root Cause
Network partition isolated the leader. The consensus layer (e.g. Patroni) was unable to renew its etcd lease, while replicas in the partition ran an election. Once the network healed, both pods remained in write mode.

### Investigation
Check Patroni cluster topology status:
```bash
kubectl exec -it postgres-0 -c postgres -- patronictl -c /etc/patroni/patroni.yml list
```

### Resolution
Manually re-initialize the out-of-sync or corrupted node to force it to replicate from the correct master:
```bash
kubectl exec -it postgres-1 -c postgres -- patronictl -c /etc/patroni/patroni.yml reinit production_db postgres-1
```
If a node refuses to step down, delete the pod. The StatefulSet will reboot it, and Patroni will force it into read-only replica status on start.

### Prevention
Configure low etcd timeout leases and run etcd on independent nodes away from database nodes.

---

## 6. Elasticsearch Shard Allocation Problems

### Symptoms
Elasticsearch cluster status is `yellow` or `red`. Queries are slow, and some documents cannot be retrieved.

### Root Cause
Unassigned shards. This happens when shards are corrupted, disk usage on a node exceeds the watermark threshold (default 85% for replication halt, 90% for active shard eviction), or nodes are missing.

### Investigation
1. Query Elasticsearch cluster health:
   ```bash
   kubectl exec -it elasticsearch-0 -- curl -s localhost:9200/_cluster/health?pretty
   ```
2. Find unassigned shards:
   ```bash
   kubectl exec -it elasticsearch-0 -- curl -s "localhost:9200/_cat/shards?h=index,shard,state,unassigned.reason" | grep UNASSIGNED
   ```

### Resolution
* **Disk Watermark Exceeded**: Scale up the PVC storage size (if `allowVolumeExpansion` is true):
  ```bash
  kubectl edit pvc elastic-data-elasticsearch-0
  # Increase storage allocation
  ```
* **Force Shard Allocation**: If a shard is unassigned after a node failure, force-allocate the primary shard (warning: potential data loss):
  ```bash
  kubectl exec -it elasticsearch-0 -- curl -XPOST -H "Content-Type: application/json" -d '{"commands":[{"allocate_empty_primary":{"index":"my_index","shard":0,"node":"elasticsearch-1","accept_data_loss":true}}]}' localhost:9200/_cluster/reroute
  ```

### Prevention
Set up automated disk expansion policies and configure `cluster.routing.allocation.disk.watermark.low` settings.

---

## 7. Pinot Server Recovery Issues

### Symptoms
Pinot queries return partial results or errors indicating segment mismatches. Pinot Server pods are failing their readiness probes.

### Root Cause
Pinot Server failed to download segments from the Controller due to controller storage issues or ZooKeeper out-of-sync states.

### Investigation
1. Check Pinot Server logs:
   ```bash
   kubectl logs pinot-server-0
   ```
2. Query Pinot Controller state for segment status:
   ```bash
   kubectl exec -it pinot-controller-0 -- curl -s localhost:9000/tables/myTable/state
   ```

### Resolution
* Restart the Pinot Server pod to force segment redownload.
* If ZooKeeper state is corrupted, use the Pinot controller admin tool to re-align table structures:
  ```bash
  kubectl exec -it pinot-controller-0 -- ./bin/pinot-admin.sh RebalanceTable -tableName myTable -tableType REALTIME
  ```

### Prevention
Dedicate solid storage to the Pinot Controller to ensure segment files are stored safely.

---

## 8. Network Partition Events (Stateful Isolations)

### Symptoms
A database node is isolated. Other nodes report it as lost, but the isolated pod still claims to be functional, running its query engine.

### Root Cause
Kubernetes network policies or CNI issues isolated the worker node containing the pod.

### Investigation
Test connectivity between StatefulSet ordinals:
```bash
kubectl exec -it db-0 -- nc -zvw3 db-1.db-headless 5432
```

### Resolution
If a node is partitioned, Kubernetes does not automatically delete the pod because it cannot verify if the pod is running or not. You must fence the node:
1. Mark the node as unschedulable:
   ```bash
   kubectl cordon node-failed
   ```
2. Drain the node to force eviction of other pods:
   ```bash
   kubectl drain node-failed --ignore-daemonsets --delete-emptydir-data
   ```

### Prevention
Ensure network firewalls permit direct communication over standard databases clustering ports (e.g. 9300 for ES, 9093 for Kafka).

---

## 9. Rolling Upgrade Failures

### Symptoms
You trigger a StatefulSet image upgrade, but the upgrade process is stuck. Only `pod-2` is updated, and it is in a `CrashLoopBackOff` or pending state. `pod-1` and `pod-0` remain on the old version.

### Root Cause
The newly updated `pod-2` failed its readiness or liveness probe. Since the StatefulSet controller requires a pod to be fully `Ready` before proceeding to update the next ordinal index, the upgrade halts, preserving the remaining cluster nodes on the old version.

### Investigation
1. Check StatefulSet rollout status:
   ```bash
   kubectl rollout status sts postgres
   ```
2. Read events and logs for the failed pod:
   ```bash
   kubectl describe pod postgres-2
   ```
   ```bash
   kubectl logs postgres-2 --tail=100
   ```

### Resolution
Roll back the update to restore the cluster state:
```bash
kubectl rollout undo sts postgres
```
Investigate the cause of the pod boot failure (e.g., config changes, schema mismatches, memory limit limits) before attempting the upgrade again.

### Prevention
Validate new container images in a development namespace before applying them to production.

---

## 10. Storage Performance Degradation

### Symptoms
Read/write query response times increase. Disk latency alerts trigger.

### Root Cause
The cloud volume is running out of burst IOPS credits, or you have hit the hard throughput limits of the instance size or disk volume tier.

### Investigation
Measure disk latency inside the database container using `ioping` or `dd` commands:
```bash
kubectl exec -it postgres-0 -- dd if=/dev/zero of=/var/lib/postgresql/data/testfile bs=1G count=1 oflag=dsync
```
Look for low write speed rates (<50MB/s indicating severe throttling).

### Resolution
1. Expand the PVC capacity (dynamic expansion will provision more IOPS on cloud environments).
2. Upgrade the `StorageClass` to use high-throughput IOPS (e.g. AWS GP3 or IO2).

### Prevention
Use `volumeBindingMode: WaitForFirstConsumer` and scale instances to support high EBS throughput rates.
