# 📝 Day 09 Core Concepts — StatefulSets and Distributed Databases

This document provides a deep architectural breakdown of Kubernetes `StatefulSets`, Headless Services, ordinal storage bindings, and the distributed systems theory (consensus, quorum, split-brain) required to run databases reliably on Kubernetes.

---

## 1. StatefulSet Mechanics: Ordinals and Lifecycle

A `StatefulSet` is a workload API object used to manage stateful applications. It manages the deployment and scaling of a set of Pods, and provides guarantees about the ordering and uniqueness of these Pods.

### The Ordinal Index
The defining characteristic of a StatefulSet is its **ordinal index**. For a StatefulSet of $N$ replicas, each Pod is assigned an integer index from $0$ up to $N-1$ that is unique and persistent across the cluster.
* If you scale up a StatefulSet from 0 replicas to 3, Pods are created sequentially: `pod-0`, then `pod-1`, then `pod-2`.
* The controller waits for `pod-0` to be `Running` and `Ready` before starting `pod-1`.
* During scale-down, Pods are terminated in reverse order: `pod-2` is terminated and completely deleted before `pod-1` is touched.

### Pod Identity and Rescheduling
Unlike a `Deployment` which generates random hashes for Pod names, a StatefulSet Pod's name is its **identity**. 

When a StatefulSet Pod is rescheduled due to a node failure:
1. The scheduler recreates the Pod on a new, healthy node.
2. The Pod is given the **exact same name** (e.g. `postgres-1`).
3. The Pod's storage templates guarantee it mounts the **exact same volume** (`pg-storage-postgres-1`) that it was using on the failed node.
4. The Pod retains its DNS name (`postgres-1.postgres-headless`).

---

## 2. Headless Services & Stable Networking

A standard Kubernetes Service uses an internal proxy (`kube-proxy`) and a virtual IP (`ClusterIP`) to load balance requests across backing Pods. This is ideal for stateless applications where any instance can handle the request.

However, database nodes are not interchangeable. Clients need to connect directly to the **Leader** to perform write operations, and replicas need direct access to each other to synchronize transaction logs. This is accomplished via a **Headless Service**.

```
Standard Service (Load Balanced)
[Client] ──► [ClusterIP: 10.96.0.10] ──► (Proxy/LB) ──┬──► [Pod-a (10.244.1.5)]
                                                     └──► [Pod-b (10.244.2.8)]

Headless Service (Direct DNS)
[Client] ──► [CoreDNS Query: db-headless]
                  │
                  ▼ Returns A Records
             [10.244.1.5, 10.244.2.8] ──► Client connects directly to target Pod
```

### Config Requirements
To define a Headless Service, set `spec.clusterIP: None`. 

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db-service
spec:
  clusterIP: None  # No ClusterIP is allocated
  selector:
    app: database
  ports:
    - port: 5432
```

### DNS Resolution Mechanics
When a Headless Service is created, CoreDNS automatically generates A records for each healthy Pod matched by the selector.

The DNS format for individual pods inside a StatefulSet is:
$$\text{DNS Record} = \text{pod-name} . \text{service-name} . \text{namespace} . \text{svc} . \text{cluster} . \text{local}$$

For a pod named `db-0` linked to a headless service `db-service` in the `default` namespace:
`db-0.db-service.default.svc.cluster.local`

This DNS record resolves directly to the Pod's current IP. If the Pod is rescheduled and its IP changes, CoreDNS updates the A record, allowing clients and peer nodes to reconnect using the same hostname.

---

## 3. Storage Architecture: Ordinal Volume Templates

StatefulSets integrate compute and storage via `volumeClaimTemplates`.

```
volumeClaimTemplates: data
        │
        ├─► StatefulSet pod-0  ──► Generates PVC: data-db-0 ──► PV: vol-01
        └─► StatefulSet pod-1  ──► Generates PVC: data-db-1 ──► PV: vol-02
```

### Dynamic Binding
When the StatefulSet Controller instantiates a Pod (e.g., `db-1`), it evaluates the `volumeClaimTemplates` block. It automatically generates a `PersistentVolumeClaim` (PVC) matching the naming pattern:
$$\text{PVC Name} = \text{claim-name} - \text{pod-name} - \text{ordinal}$$

The Kubernetes volume controller watches this PVC and, if a `StorageClass` is configured, dynamically provisions a `PersistentVolume` (PV) on the cloud provider, binding the volume 1-to-1 with `db-1`.

### Safety Guarantee: PVC Retention
When a StatefulSet is scaled down or even deleted entirely, **the generated PVCs are NOT deleted**. This is a safety feature by design to prevent accidental data loss. 

If you scale a StatefulSet down from 3 to 1:
1. Pods `db-2` and `db-1` are terminated.
2. PVCs `data-db-2` and `data-db-1` remain in the cluster.
3. The underlying PVs remain bound.
4. If you scale back up, `db-1` and `db-2` are recreated and automatically reattached to `data-db-1` and `data-db-2`, resuming where they left off.
5. If you want to delete the data, you must manually delete the PVCs after deleting the StatefulSet.

---

## 4. Distributed Systems & Consensus Basics

Running database clusters on Kubernetes requires understanding how distributed engines maintain consensus and data integrity across a network that is prone to latencies and partitions.

### The Quorum Rule
To agree on cluster state (e.g. who is the current leader, whether a write is committed), distributed databases rely on a **quorum**. A quorum is defined as a strict majority of nodes:
$$\text{Quorum} = \left\lfloor \frac{N}{2} \right\rfloor + 1$$

Where $N$ is the total number of voting members in the cluster.

| Cluster Size ($N$) | Quorum Size ($Q$) | Max Tolerated Failures |
| :---: | :---: | :---: |
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 5 | 3 | 2 |
| 7 | 4 | 3 |

> [!IMPORTANT]
> Clusters should always be deployed with an **odd number** of nodes (3, 5, 7). An even number of nodes (e.g. 4) increases cost without improving fault tolerance (both 3-node and 4-node clusters require a quorum of 2, meaning both tolerate exactly 1 node failure).

### Split-Brain & Consensus Protocols
If a network partition divides a 3-node cluster into two isolated network segments:
* **Segment A**: Contains `node-0` (previous leader).
* **Segment B**: Contains `node-1` and `node-2`.

```
  [ node-0 ]      X  Network  X      [ node-1 ]  <───►  [ node-2 ]
(Isolated Node)   X  Barrier  X     (Quorum Segment: 2 nodes)
  Can't reach                        Can reach majority, running
  majority.                          a new leader election.
```

If consensus protocols are not configured correctly, `node-0` might continue accepting writes, while `node-1` and `node-2` run an election and promote `node-1` to leader. This results in **Split-Brain**—two nodes acting as write-leaders, writing conflicting data. When the network heals, the database cannot merge the conflicting histories, causing severe data corruption.

Consensus protocols prevent this:
* **Raft (Kafka KRaft, etcd)** / **Zab (ZooKeeper)**: In Segment A, `node-0` notices it cannot communicate with the majority of voters ($1 < Q$). It immediately demotes itself to a read-only or inactive state. In Segment B, `node-1` and `node-2` form a quorum ($2 \ge Q$), elect `node-1` as the new leader, and continue processing writes safely.

### Write-Ahead Log (WAL) and Durability
Before updating tables in memory, a database appends the change to the **Write-Ahead Log (WAL)** on persistent storage.
1. The transaction is written to the WAL.
2. The WAL buffer is flushed to physical disk (`fsync`).
3. The change is applied to the memory database.
4. The client is notified of success.

If the container dies at step 3, the database reads the WAL on recovery to restore the in-memory database to a consistent state. If Kubernetes storage lacks durability guarantees, or if `fsync` is disabled for performance, crash-recovery is impossible.

---

## 5. Architectural Deep Dive: Day 9 Target Databases

### I. PostgreSQL (Active-Passive)
* **Write Path**: Directed entirely to the Leader pod.
* **Read Path**: Can be distributed across replicas.
* **Sync Mechanisms**: Uses Streaming Replication. Replicas pull WAL files from the leader.
* **K8s Implementation**: Relies on a headless service for stable names. For HA, controllers like `Patroni` run inside the containers, query an external store (like etcd), and configure postgres dynamically to handle promotions.

### II. Apache Kafka (Distributed Log Stream)
* **KRaft Consensus**: Replaces ZooKeeper. Kafka brokers act as controller nodes, executing Raft metadata replication internally.
* **Partition Replication**: Partitions are divided into leaders and followers. Writes go to partition leaders, which replicate logs to ISR (In-Sync Replicas).
* **K8s Implementation**: The StatefulSet provides ordinal broker IDs (`node.id=0`, `node.id=1`, `node.id=2`). Headless DNS allows brokers to route inter-broker replication traffic efficiently.

### III. Elasticsearch (Distributed Document Index)
* **Master Nodes**: Handle index creation, node routing, and cluster mapping.
* **Sharding**: Indices are split into shards. Primary shards write and replicate to replica shards.
* **K8s Implementation**: Uses stateful storage to prevent rebuilding massive index directories upon pod rescheduling. Uses `discovery.seed_hosts` pointing to the Headless DNS for discovery.

### IV. Apache Pinot (Distributed Real-time OLAP)
* **Zookeeper Coordinator**: Tracks cluster configuration and tables.
* **Controller**: Manages cluster state and segments. Runs as a StatefulSet to maintain metadata.
* **Server**: Stores analytics segment files. Runs as a StatefulSet to hold large volumes of data on persistent disks.
* **Broker**: Routes queries. Runs as a stateless Deployment because it does not store local segment data.
