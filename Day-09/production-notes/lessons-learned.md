# ⚡ Day 09 Production Notes — Lessons Learned Operating Distributed Databases at Scale

This document shares hard-earned operational insights, failure modes, and architectural guidelines for managing stateful distributed systems (PostgreSQL, Kafka, Elasticsearch, Pinot) under high load in production Kubernetes environments.

---

## 1. Split-Brain Mitigation & Quorum Realities

In a virtualized Kubernetes network, network partitions (brief packet drops, routing loops, or overloaded CoreDNS instances) are inevitable. When a partition occurs, it splits the database cluster into isolated segments.

### The Danger: Split-Brain
If two segments believe they are the authoritative leaders, both will accept writes. When the network partition heals, you are left with **divergent data history**. Merging this data is complex and often leads to data loss or corruption.

### Production Rules:
* **Enforce Odd Replica Counts**: Maintain a minimum of 3 replicas for any distributed consensus system. 5 is standard for mission-critical metadata stores (like etcd, Consul, ZooKeeper).
* **Quorum Checks**: Configure databases to automatically step down or demote if they lose connection to a majority quorum.
  * In **Kafka (KRaft)**: Set `unclean.leader.election.enable=false` to prevent out-of-sync replicas from being elected as leaders.
  * In **PostgreSQL (Patroni)**: Set lease TTLs carefully (e.g. `ttl: 30`, `loop_wait: 10`). If Patroni cannot renew its lease in etcd within the TTL, it immediately demotes the PostgreSQL leader to a read-only replica.
* **Anti-Affinity**: Prevent database replicas from running on the same physical host node using Pod Anti-Affinity. If Node-A crashes, you lose only one replica, and the remaining replicas retain quorum.

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - postgres
          topologyKey: "kubernetes.io/hostname"
```

---

## 2. Managing Replication Lag

Replication lag occurs when follower nodes cannot process WAL files or logs as fast as the leader writes them.

### Causes of Replication Lag:
1. **Network Bandwidth**: High network latency between availability zones.
2. **Compute Starvation**: Followers are resource-throttled due to low CPU limits.
3. **Storage Write Speed**: Follower volumes are configured with slower disk IOPS (e.g., AWS GP2 instead of GP3 or io2).

### Production Rules:
* **Match Resource Allocation**: Replicas must have the *exact* same CPU and Memory requests and limits as the leader. Throttling CPU on replicas will directly cause replication lag.
* **Heap Space Tuning**: For Java workloads (Elasticsearch, Pinot, Kafka), JVM garbage collection pauses can stall replication. Set `ES_JAVA_OPTS` or `KAFKA_JVM_PERFORMANCE_OPTS` to use exactly 50% of the container memory limits, leaving the rest for the OS page cache.
* **Monitor ISR (In-Sync Replicas) in Kafka**: Alert immediately if `UnderReplicatedPartitions` is greater than 0. Under-replicated partitions mean a node failure could lead to data loss.

---

## 3. Storage Bottlenecks & Disk Tuning

Kubernetes storage classes abstract away details, but cloud disks have strict physical limits.

### The GP3 IOPS Trap
In AWS, standard GP3 volumes provide a baseline performance of 3,000 IOPS and 125 MB/s throughput. Once your database exceeds this limit, the cloud provider throttles disk operations. In Kubernetes, this displays as:
* Extremely high disk wait times (`iowait` > 20%).
* StatefulSet pods failing their readiness probes because the database engine is blocked on disk writes.
* Database connections pooling and hitting timeout limits.

### Production Rules:
* **Custom StorageClasses**: Do not use the default generic storage class. Define a custom class with optimized parameters:
  ```yaml
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: db-gp3
  provisioner: ebs.csi.aws.com
  volumeBindingMode: WaitForFirstConsumer
  parameters:
    type: gp3
    iops: "6000" # Provisioned IOPS
    throughput: "250" # Provisioned throughput (MB/s)
  allowVolumeExpansion: true
  ```
* **Use Local NVMe for OLAP (Pinot/Elasticsearch)**: For Apache Pinot and Elasticsearch where reads are extremely intensive, network-attached storage introduces latency. Utilizing host-local NVMe disks (via Local Persistent Volumes) provides massive speedups, but requires replication strategies to handle host node terminations.

---

## 4. Stateful Rolling Upgrade Strategies

Upgrading the container image of a StatefulSet requires planning. Unlike Deployments, you cannot just terminate all pods.

### The Upgrade Sequence
Kubernetes upgrades StatefulSets in **reverse ordinal order** (from $N-1$ down to $0$).
For a 3-replica cluster:
1. `pod-2` is terminated, updated, and booted.
2. The controller waits for `pod-2` to be `Ready` (passing its readiness probe).
3. `pod-1` is terminated, updated, and booted.
4. `pod-0` (usually the leader) is updated last.

### Production Rules:
* **Write Realistic Readiness Probes**: The readiness probe must check if the database has successfully synchronized state and joined the cluster cluster, not just if the process is running. If `pod-2` boots but cannot sync, the upgrade must halt. If your probe is too simple (e.g. just a TCP socket check on port 5432), Kubernetes will mark it ready, proceed to terminate `pod-1`, and successfully take down the entire database cluster.
* **PodDisruptionBudgets (PDB)**: Always define a PDB for your StatefulSet to prevent automated Kubernetes operations (like node draining or cluster upgrades) from taking down too many database replicas at once:
  ```yaml
  apiVersion: policy/v1
  kind: PodDisruptionBudget
  metadata:
    name: postgres-pdb
  spec:
    maxUnavailable: 1
    selector:
      matchLabels:
        app: postgres
  ```

---

## 5. Backup, Restore, and Disaster Recovery (DR)

Relying on Persistent Volumes is not a backup strategy. If a cluster namespace is deleted, or a ransomware attack compromises the cloud account, your live data is lost.

### Production Rules:
* **Decouple Backup Execution**: Run backups from a separate CronJob or utility container, dumping database states (e.g., `pg_dump` or Kafka mirror maker) directly to off-cluster object storage (like AWS S3 with Object Lock enabled for immutability).
* **Automated Volume Snapshots**: Utilize CSI Volume Snapshots to capture block-level backups. Define a `VolumeSnapshotClass` and create `VolumeSnapshot` CRDs on a cron schedule.
* **Test the Restore Path**: The absolute rule of database reliability engineering: **An untested backup is a failed backup.** Automate a pipeline that spins up a ephemeral namespace weekly, restores the database from the latest snapshot, runs basic validation queries, and tears it down.
