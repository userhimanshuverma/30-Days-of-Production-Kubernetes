# Running Data Platforms on Kubernetes: Architecture & Design

Historically, databases, messaging queues, and analytical platforms were run on dedicated bare-metal or virtual machines. Operating these platforms in static silos led to low resource utilization, high maintenance costs, and severe scaling friction. 

Today, Kubernetes is the standard control plane for modern data platforms. This document details the architectural paradigms of running Spark, Airflow, Kafka, and Pinot in cloud-native production environments.

---

## 1. Why Data Platforms Moved to Kubernetes

The transition from dedicated VM silos to containerized platforms is driven by operational efficiency, agility, and scaling speed:

```
Traditional VM Silos             Cloud-Native Data Platform (K8s)
┌───────────┐ ┌───────────┐      ┌────────────────────────────────┐
│   Kafka   │ │   Spark   │      │        K8s Control Plane       │
│  (Static) │ │  (Static) │      │ ┌─────────┐┌─────────┐┌──────┐ │
├───────────┤ ├───────────┤  ──> │ │  Kafka  ││  Spark  ││Pinot │ │
│  VM / OS  │ │  VM / OS  │      │ │  (StS)  ││ (Batch) ││(OLAP)│ │
├───────────┤ ├───────────┤      │ └─────────┘└─────────┘└──────┘ │
│ Hardware  │ │ Hardware  │      ├────────────────────────────────┤
└───────────┘ └───────────┘      │     Dynamic Shared Hardware    │
                                 └────────────────────────────────┘
```

### The Inefficiency of Traditional Infrastructure
1. **Resource Silos**: A Spark cluster size was fixed to support peak load. During idle hours, these machines sat inactive, costing thousands.
2. **Configuration Drift**: VM-based updates using Ansible or Puppet frequently resulted in discrepancies where certain nodes held different library versions or OS patches.
3. **No Native API Control**: Scaling required external VM provisioning pipelines that took minutes or hours, rather than seconds.

### The Kubernetes Solution
* **Unified Control Plane**: Run stateless web servers, stateful streaming buffers (Kafka), batch processing engines (Spark), and real-time analytical layers (Pinot) on the same compute hardware.
* **Declarative Configuration**: Infrastructure is defined as code (YAML/CRDs) and managed by active control loops (Operators) to prevent config drift.
* **Elastic Autoscaling**: Scale resources dynamically based on runtime metrics (e.g., CPU load, Kafka topic lag, memory footprint) and automatically reclaim compute resources when batch jobs finish.

---

## 2. Apache Spark on Kubernetes Architecture

Apache Spark runs natively on Kubernetes using the **K8s Scheduler Backend**. When a Spark job is submitted, the Kubernetes API acts as the cluster manager.

```
[Client / submit] ──> [K8s API Server] ──> [Spawns Driver Pod]
                                                 │
   ┌─────────────────────────────────────────────┼─────────────────────────────────────────────┐
   │                                             ▼                                             │
   │                                   Requests Executor Pods                                  │
   │                                             │                                             │
   ▼                                             ▼                                             ▼
[Executor Pod 1]                          [Executor Pod 2]                          [Executor Pod N]
 - Runs Task A                             - Runs Task B                             - Runs Task C
 - Mounts emptyDir (Shuffle)               - Mounts emptyDir (Shuffle)               - Mounts emptyDir (Shuffle)
```

### Spark Component Roles
* **Spark Driver Pod**: Initiates the `SparkContext`, contacts the Kubernetes API server, requests the creation of Executor pods, schedules execution tasks, coordinates data shuffling, and collects results.
* **Spark Executor Pods**: Dynamically spawned on worker nodes to execute task workloads, read data partitions, and write intermediate shuffle files to local storage mounts.
* **Dynamic Resource Allocation**: With dynamic allocation enabled, the Driver monitors pending task queues. If tasks are blocked, the Driver requests more Executor pods from the API. If executors remain idle (default: `30s`), they are terminated, returning compute resources to the cluster.

---

## 3. Apache Airflow on Kubernetes: Kubernetes Executor

Traditional Airflow setups rely on Celery workers, which run continuously and require RabbitMQ or Redis for queue management. The **Kubernetes Executor** eliminates the queue daemon and manages worker pods dynamically.

```
[Airflow Scheduler] ──> Calls K8s API ──> Spawns [Worker Pod A (Task 1)]
         │                                Spawns [Worker Pod B (Task 2)]
         ▼
[Postgres Metadata DB] <── Writes status updates ── [Reclaimed on success]
```

### Lifecycle of a Task Execution
1. **DAG Parsing**: The Airflow Scheduler parses the DAG files.
2. **Task State Assignment**: When a task is ready to run, the Scheduler calls the Kubernetes API directly to spawn a dedicated worker pod.
3. **Worker Execution**: The worker pod runs a single command (e.g., `airflow tasks run ...`), using an image pre-loaded with the execution dependencies.
4. **State Persistence**: The worker writes its progress and status (success/failure) back to the Postgres metadata database.
5. **Reconciliation**: The worker pod exits, and the Kubernetes API reaps the pod.

### Celery vs. Kubernetes Executor
* **Celery Executor**: Faster task startup latency (workers are already warm), but requires running static worker pools that waste memory when no DAGs are scheduled.
* **Kubernetes Executor**: Higher startup latency (requires scheduling and pulling images), but achieves absolute resource isolation, permits custom images per task, and scales down to zero worker pods.

---

## 4. Apache Kafka on Kubernetes

Running Apache Kafka on Kubernetes is challenging because Kafka is a high-throughput, low-latency stateful system requiring persistent identity, stable storage, and zero-downtime rolling updates.

```
                  [Strimzi Kafka Operator]
                             │
            Monitors & reconciles Kafka StatefulSet
                             │
     ┌───────────────────────┼───────────────────────┐
     ▼                       ▼                       ▼
[Kafka Broker 0]        [Kafka Broker 1]        [Kafka Broker 2]
  - Pod Identity 0        - Pod Identity 1        - Pod Identity 2
  - PVC 0 (local NVMe)    - PVC 1 (local NVMe)    - PVC 2 (local NVMe)
  - Headless Service      - Headless Service      - Headless Service
```

### StatefulSet & Headless Service Mechanics
* **StatefulSet**: Ensures that each Kafka Broker pod receives a persistent index (e.g., `kafka-0`, `kafka-1`, `kafka-2`). If a pod dies, the scheduler recreates it with the exact same hostname and binds it to the same PersistentVolume.
* **Headless Service**: Disables load-balancing, providing unique DNS records for each broker (e.g., `kafka-0.kafka-headless.default.svc.cluster.local`). This is critical because Kafka clients must establish direct TCP connections to the specific broker partition leader.
* **Volume Persistence**: Each broker requires a PersistentVolumeClaim (PVC). Standard SSDs (EBS gp3) or local NVMe disks are used to handle heavy disk write I/O.
* **Operator Pattern (Strimzi)**: Automates rolling upgrades, configures listener certificates, manages Kafka Topics (`KafkaTopic` CRD), and safely coordinates broker restarts without triggering partition offline events.

---

## 5. Apache Pinot on Kubernetes

Apache Pinot is a real-time distributed OLAP datastore designed for low-latency analytical queries on large datasets. Pinot has a multi-service architecture that maps cleanly to Kubernetes.

```
                         [Query Client]
                                │
                                ▼
                       [Pinot Broker Pods]
                                │  (Scatter-Gather)
                 ┌──────────────┴──────────────┐
                 ▼                             ▼
        [Pinot Server 0]              [Pinot Server 1]  <── Consumes Real-time from Kafka
      (Offline / Segment 0)         (Real-time / Segment 1)
                 │                             │
                 └──────────────┬──────────────┘
                                ▼
                   [ZooKeeper Consensus Store]
```

### Pinot Component Mapping on Kubernetes
1. **Controller (Deployment/StatefulSet)**: Manages cluster state, routes, schema configs, and coordinates offline ingestion jobs. Integrates with ZooKeeper.
2. **Broker (Deployment)**: The query entrypoint. Accepts SQL queries from clients, checks the ZooKeeper routing table, scatters queries across the appropriate Server pods, gathers the individual segment results, and merges them into a single JSON response.
3. **Server (StatefulSet)**: The workhorse. Ingests streaming events from Kafka, indexes data into immutable segments, processes local segment scans during queries, and mounts persistent NVMe SSDs to store segments locally.
4. **Minion (Deployment)**: Executes background administration tasks, such as segment compaction, consolidation, and purging.
5. **ZooKeeper**: Serves as the single source of truth for segment metadata, cluster routing tables, and server states.

---

## 6. Stateful Workload Challenges on Kubernetes

To run data platforms reliably on Kubernetes, engineers must solve several fundamental physical challenges:

### Data Gravity & Persistent Volume Bindings
Unlike stateless pods, database pods cannot be scheduled arbitrarily.
* **Storage Latency**: Network-attached volumes (e.g., AWS EBS) add network hops, increasing latency. Direct-attached local NVMe SSDs solve this but lock the pod to a single physical worker node.
* **Volume Scheduling Mismatch**: If a pod is scheduled in `us-east-1a`, its PVC must also reside in `us-east-1a`. Using `volumeBindingMode: WaitForFirstConsumer` is mandatory to ensure the scheduler matches the pod's node location with the volume's availability zone.

### Network Throughput & Node Topology
* **Intra-Cluster Network Saturation**: Kafka replication and Spark shuffle phases generate immense East-West network traffic.
* **Cross-AZ Cost Allocation**: If Kafka brokers replicate partitions across AZs, cloud providers charge heavy cross-AZ network fees. Hardening affinity rules is crucial to control data transfers.
* **Headless Service DNS Delays**: Large-scale Pinot queries require Broker pods to lookup routing info. A slow DNS server (CoreDNS) causes microsecond query delays to balloon into seconds. Using `NodeLocal DNSCache` is a production requirement.

### Resource Contention (Noisy Neighbors)
If a Spark executor runs on the same node as a Pinot Server, the Spark job's CPU utilization spikes can starve the Pinot server, violating sub-second query SLAs.
* **Namespace Quotas**: Restrict maximum resources allocatable per team.
* **Pod Priority Classes**: Assign critical system pods (Kafka, Pinot Controller) high priority so the scheduler evicts low-priority batch pods (Spark Executors) in the event of resource starvation.
