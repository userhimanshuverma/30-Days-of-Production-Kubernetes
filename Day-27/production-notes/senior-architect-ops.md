# Operating Cloud-Native Data Platforms at Scale: SRE & SRE-Ops Playbook

Running distributed stateful systems on Kubernetes requires moving beyond default configurations. This document outlines the patterns, configuration guidelines, and operational lessons compiled from running high-throughput production data platforms.

---

## 1. Storage Performance & CSI Hardening

Storage is the most common failure point for databases on Kubernetes. Default storage classes are unsuited for systems like Kafka and Pinot.

### gp3 vs. Local NVMe SSDs
* **EBS gp3**: Network-attached storage. Good for elasticity (easy resizing, backup snapshots). However, it adds network latency and has performance ceilings (max 16,000 IOPS, 1,000 MB/s throughput).
* **Local NVMe SSDs**: Directly attached to physical hosts. Provides ultra-low sub-millisecond latency and >500,000 IOPS. Essential for Pinot Servers and high-throughput Kafka partitions.
* **The Trade-Off**: If the physical host dies, the local NVMe data is lost. Therefore, application-level replication (e.g., Kafka replication factor = 3, Pinot replication = 2) must handle recovery.

### StorageClass Configurations
For network-attached volumes, optimize parameters for IOPS and throughput:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-data-optimized
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer # Critical: delays PV creation until Pod scheduling node is determined
reclaimPolicy: Retain                   # Critical: prevents data deletion if the PVC is accidentally deleted
allowVolumeExpansion: true
parameters:
  type: gp3
  iops: "10000"                         # Manually override baseline 3000 IOPS
  throughput: "500"                     # Manually override baseline 125 MB/s
  encrypted: "true"
```

### Mount Options
When mounting data volumes for database engines, modify the filesystem mount options in the storage driver or pod specification. Add `noatime` and `nodiratime` to prevent the OS from writing access times back to disk for every read query:
`mount -o noatime,nodiratime,data=writeback /dev/xvdb /var/lib/kafka/data`

---

## 2. Resource Isolation & QoS Enforcement

Data workloads generate CPU, memory, and IO resource spikes. Without isolation, these workloads can starve other processes on the host.

### QoS Classes: Guaranteed vs. Burstable
* **Guaranteed (Request == Limit)**: Set this for stateful pods (Kafka, Pinot Controller, Pinot Server, PostgreSQL). This prevents the kernel from out-of-memory (OOM) killing database processes during host memory spikes.
* **Burstable (Request < Limit)**: Acceptable for stateless batch executors (Spark Executors) or Airflow workers, where worker pod eviction is tolerated and handled by retries.

### Node Allocatable & Reserve Configurations
If worker nodes run out of memory, the Kubelet itself can crash, taking down all running pods. Always configure `kube-reserved` and `system-reserved` flags in the Kubelet configuration to reserve CPU and memory for daemon services:
* `kube-reserved`: cpu=1000m,memory=2Gi
* `system-reserved`: cpu=500m,memory=1Gi

### Scheduling Policies
Use Taints and Tolerations to partition nodes into distinct pools:

```
  [On-Demand Node Pool]                [Spot Node Pool]
   (No Taints: Standard)             (Taint: spot=true:NoSchedule)
      ┌───────────┐                        ┌───────────┐
      │   Kafka   │                        │   Spark   │
      │ Broker Pod│                        │ Executor  │
      └───────────┘                        └───────────┘
```
1. **Node Selectors & Affinities**: Pin Kafka and Pinot to reliable On-Demand Node Groups spread across multiple zones.
2. **Taints & Tolerations**: Run Spark Dynamic Executors and Airflow Task Workers on cheap Spot Instance Node Groups. Configure a toleration in the executor pod specification so that they can be scheduled on these tainted spot instances.

---

## 3. Dynamic Autoscaling with KEDA (Kubernetes Event-driven Autoscaling)

Horizontal Pod Autoscalers (HPAs) rely on CPU/Memory usage. For data platforms, scaling based on CPU is too slow and can lead to data delays.

### Kafka Lag-Based Autoscaling
If an ingestion pipeline experiences a data spike, the consumer pods (running Spark Streaming or Python consumers) will fall behind. We configure **KEDA** to monitor the Kafka offset lag directly from Kafka brokers.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: telemetry-consumer
  minReplicaCount: 1
  maxReplicaCount: 12
  cooldownPeriod:  300
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: production-kafka-kafka-bootstrap.default.svc.cluster.local:9092
        consumerGroup: production-analytics-consumers
        topic: user-clicks
        lagThreshold: "1000" # Scale up if lag exceeds 1000 records
```

---

## 4. Cost Optimization & Multi-Tenancy

Data infrastructure accounts for the majority of cloud costs. To control expenses, implement these patterns:

1. **Spot Instances for Spark Executors**: Spark is designed to handle executor loss. If an executor pod is preempted, the Spark Driver automatically reschedules the task on another executor. Enabling Spot Instances reduces compute costs by up to 80%.
2. **Tiered Storage (Kafka & Pinot)**:
   * **Hot Tier**: Store the last 24 hours of data on high-performance Local NVMe SSDs.
   * **Cold Tier**: Offload older segments/files to cheap Cloud Object Stores (Amazon S3 / Google Cloud Storage) at a fraction of the cost.
3. **Namespace ResourceQuotas**: Set resource quotas per namespace to prevent any single engineering team from launching massive clusters that exhaust the entire host pool:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: spark-compute-quota
  namespace: default
spec:
  hard:
    requests.cpu: "40"
    requests.memory: "160Gi"
    limits.cpu: "80"
    limits.memory: "320Gi"
    pods: "100"
```

---

## 5. Real-World Case Studies: Production Outages

### Case Study 1: The CoreDNS Bottleneck
* **Symptom**: Pinot queries experienced periodic timeouts (HTTP 504), even though the servers had 50% CPU headroom.
* **Root Cause**: Pinot Brokers lookup Pinot Server IP addresses before routing queries. With thousands of queries per second, this saturated the CoreDNS pods, causing DNS lookup timeouts.
* **Resolution**: Implemented `NodeLocal DNSCache` on all worker nodes. This caches DNS lookups locally on the host's loopback interface, eliminating CoreDNS network hops and reducing query latency by 90%.

### Case Study 2: The Cascading JVM GC Pause
* **Symptom**: A Kafka broker was marked as unhealthy, triggering broker evictions and partition offline warnings.
* **Root Cause**: The broker JVM was misconfigured with a small heap size. A sudden spike in client requests triggered a full Garbage Collection (GC) pause. The pause exceeded the ZooKeeper session timeout (`10s`), causing Zookeeper to assume the broker died. The broker was evicted, which forced other brokers to take over the traffic, triggering GC pauses on them as well (cascading failure).
* **Resolution**: Increased JVM GC configuration to use G1GC with explicit maximum pause targets:
  `-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=45`
  Additionally, tuned Zookeeper session timeouts (`zookeeper.connection.timeout.ms=18000`).
