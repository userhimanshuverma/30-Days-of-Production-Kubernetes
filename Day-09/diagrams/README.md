# 📊 Day 09 Diagrams — StatefulSet & Database Architectures

This page contains professional, enterprise-grade architecture diagrams visualizing the internal mechanics of StatefulSets and distributed database clustering on Kubernetes.

---

## 1. Deployment vs. StatefulSet

This diagram highlights the differences in how Deployments and StatefulSets manage Pod naming, networking, and storage mapping.

```mermaid
graph TD
    subgraph "Deployment (Stateless)"
        dep[Deployment Controller] --> rep_dep[ReplicaSet]
        rep_dep --> pod_d1[Pod: web-7ab8f]
        rep_dep --> pod_d2[Pod: web-9cf1a]
        pod_d1 -.-> pvc_d[Single Shared PVC / No PVC]
        pod_d2 -.-> pvc_d
        svc_d[Standard LoadBalancer Service] --> pod_d1
        svc_d --> pod_d2
    end

    subgraph "StatefulSet (Stateful)"
        sts[StatefulSet Controller] --> pod_s0[Pod: db-0]
        sts --> pod_s1[Pod: db-1]
        pod_s0 --> pvc_s0[PVC: data-db-0]
        pod_s1 --> pvc_s1[PVC: data-db-1]
        pvc_s0 --> pv_s0[PV: vol-001]
        pvc_s1 --> pv_s1[PV: vol-002]
        svc_s[Headless Service: db-headless]
        svc_s -.->|db-0.db-headless| pod_s0
        svc_s -.->|db-1.db-headless| pod_s1
    end

    style dep fill:#5f27cd,stroke:#341f97,stroke-width:2px,color:#fff
    style sts fill:#5f27cd,stroke:#341f97,stroke-width:2px,color:#fff
    style pod_d1 fill:#222f3e,stroke:#576574,stroke-width:1px,color:#fff
    style pod_d2 fill:#222f3e,stroke:#576574,stroke-width:1px,color:#fff
    style pod_s0 fill:#10ac84,stroke:#0f8f6b,stroke-width:2px,color:#fff
    style pod_s1 fill:#10ac84,stroke:#0f8f6b,stroke-width:2px,color:#fff
```

---

## 2. StatefulSet Architecture

A structural view of the StatefulSet environment. The controller coordinates scheduling, mapping ordinal index pods to unique persistent volume claims.

```mermaid
graph LR
    sts[StatefulSet: postgres] --> pod0[Pod: postgres-0]
    sts --> pod1[Pod: postgres-1]
    sts --> pod2[Pod: postgres-2]

    subgraph "DNS & Networking Plane"
        headless[Headless Service: postgres-headless]
        headless -.->|postgres-0.postgres-headless| pod0
        headless -.->|postgres-1.postgres-headless| pod1
        headless -.->|postgres-2.postgres-headless| pod2
    end

    subgraph "Storage Plane (1:1 Bound)"
        pod0 --> pvc0[PVC: pg-storage-postgres-0]
        pod1 --> pvc1[PVC: pg-storage-postgres-1]
        pod2 --> pvc2[PVC: pg-storage-postgres-2]
    end

    style sts fill:#5f27cd,stroke:#341f97,color:#fff
    style headless fill:#341f97,stroke:#222f3e,color:#fff
    style pod0 fill:#00d2d3,stroke:#01a3a4,color:#000
    style pod1 fill:#00d2d3,stroke:#01a3a4,color:#000
    style pod2 fill:#00d2d3,stroke:#01a3a4,color:#000
```

---

## 3. Stable Pod Identity Workflow

This sequence shows how a Pod retains its hostname and storage binding across a rescheduling event (e.g. node crash).

```mermaid
sequenceDiagram
    autonumber
    participant K as Kube-Scheduler
    participant N1 as Host Node A
    participant N2 as Host Node B
    participant PV as PersistentVolume (pv-vol-1)
    participant DNS as CoreDNS

    Note over N1,PV: Pod postgres-1 is running on Node A
    N1->>PV: Mounts pg-storage-postgres-1
    DNS->>N1: Resolve postgres-1.postgres-headless -> 10.244.1.45

    Note over N1: Node A goes Down (Network Partition)
    K->>N1: Evict Pod postgres-1 (Terminating)
    K->>PV: Detach Volume from Node A
    K->>N2: Schedule postgres-1 (Ordinal preserved)
    N2->>PV: Attach & Mount pg-storage-postgres-1
    N2->>DNS: Register postgres-1.postgres-headless -> 10.244.2.89
    Note over N2,PV: Pod postgres-1 is healthy and reading previous data
```

---

## 4. Persistent Storage Binding

Visualization of `volumeClaimTemplates` generating independent claims rather than sharing a volume.

```mermaid
graph TD
    subgraph "Template"
        vct[volumeClaimTemplates: pg-storage]
    end

    subgraph "Generated PVCs"
        pvc0[PVC: pg-storage-postgres-0]
        pvc1[PVC: pg-storage-postgres-1]
    end

    subgraph "Cloud PVs"
        pv0[PV: aws-ebs-gp3-01]
        pv1[PV: aws-ebs-gp3-02]
    end

    vct -->|instantiates| pvc0
    vct -->|instantiates| pvc1
    pvc0 -->|Binds 1:1| pv0
    pvc1 -->|Binds 1:1| pv1

    style vct fill:#ff9f43,stroke:#ee5253,color:#000
    style pvc0 fill:#2e86de,stroke:#0abde3,color:#fff
    style pvc1 fill:#2e86de,stroke:#0abde3,color:#fff
```

---

## 5. Kafka Cluster Architecture (KRaft Mode)

A 3-node Apache Kafka cluster running without ZooKeeper. The controllers form a raft quorum via port 9093, and clients publish logs on port 9092.

```mermaid
graph TD
    subgraph "Clients"
        producer[Producer Client]
        consumer[Consumer Client]
    end

    subgraph "KRaft Kafka Cluster"
        k0["Pod: kafka-0<br/>(Broker, Controller)<br/>ID: 0"]
        k1["Pod: kafka-1<br/>(Broker, Controller)<br/>ID: 1"]
        k2["Pod: kafka-2<br/>(Broker, Controller)<br/>ID: 2"]
    end

    subgraph "Consensus Quorum"
        k0 <-->|Raft Voting / Sync<br/>Port 9093| k1
        k1 <-->|Raft Voting / Sync<br/>Port 9093| k2
        k2 <-->|Raft Voting / Sync<br/>Port 9093| k0
    end

    producer -->|Write Log<br/>Port 9092| k0
    consumer -->|Read Log<br/>Port 9092| k1

    style k0 fill:#10ac84,stroke:#0f8f6b,color:#fff
    style k1 fill:#10ac84,stroke:#0f8f6b,color:#fff
    style k2 fill:#10ac84,stroke:#0f8f6b,color:#fff
```

---

## 6. PostgreSQL Replication (Leader-Follower)

PostgreSQL running with one Read-Write Leader and two Read-Only Replicas.

```mermaid
graph TD
    client_w[Client Writes] -->|Port 5432| svc_w[Write Service]
    client_r[Client Reads] -->|Port 5432| svc_r[Read Service]

    subgraph "Postgres StatefulSet"
        pg0["Pod: postgres-0<br/>(Leader / Read-Write)"]
        pg1["Pod: postgres-1<br/>(Replica / Read-Only)"]
        pg2["Pod: postgres-2<br/>(Replica / Read-Only)"]
    end

    svc_w --> pg0
    svc_r --> pg1
    svc_r --> pg2

    pg0 -->|Streaming Replication<br/>WAL Sync| pg1
    pg0 -->|Streaming Replication<br/>WAL Sync| pg2

    style pg0 fill:#ee5253,stroke:#c0392b,color:#fff
    style pg1 fill:#2e86de,stroke:#2980b9,color:#fff
    style pg2 fill:#2e86de,stroke:#2980b9,color:#fff
```

---

## 7. Elasticsearch Cluster Topology

Elasticsearch nodes dynamically discover each other using Headless DNS and form a master quorum while distributing index shards.

```mermaid
graph TD
    subgraph "Headless DNS Group"
        es0["Pod: elasticsearch-0<br/>(Master/Data)"]
        es1["Pod: elasticsearch-1<br/>(Master/Data)"]
        es2["Pod: elasticsearch-2<br/>(Master/Data)"]
    end

    es0 <-->|Transport Port 9300<br/>Zen Discovery| es1
    es1 <-->|Transport Port 9300<br/>Zen Discovery| es2
    es2 <-->|Transport Port 9300<br/>Zen Discovery| es0

    subgraph "Data Distribution (Sharding)"
        es0 -->|Shard R1| es1
        es1 -->|Shard R2| es2
        es2 -->|Shard R3| es0
    end

    client[REST Clients] -->|HTTP Port 9200| es0

    style es0 fill:#00d2d3,stroke:#01a3a4,color:#000
    style es1 fill:#00d2d3,stroke:#01a3a4,color:#000
    style es2 fill:#00d2d3,stroke:#01a3a4,color:#000
```

---

## 8. Apache Pinot Architecture

Pinot decouples storage and query execution, showing stateful and stateless components on Kubernetes.

```mermaid
graph TD
    subgraph "Coordination Plane"
        zk[ZooKeeper Cluster]
    end

    subgraph "Pinot Control Plane"
        ctrl["Pinot Controller (StatefulSet)<br/>(Metadata Coordinator)"]
    end

    subgraph "Pinot Query Layer"
        broker["Pinot Broker (Deployment)<br/>(Stateless Router)"]
    end

    subgraph "Pinot Storage & Execution Layer"
        srv0["Pinot Server: pinot-server-0<br/>(Segment Datastore)"]
        srv1["Pinot Server: pinot-server-1<br/>(Segment Datastore)"]
    end

    client[Analytic Client] -->|SQL Query| broker
    broker -->|Route Queries| srv0
    broker -->|Route Queries| srv1
    ctrl -->|Helix Sync| zk
    srv0 -->|Helix state| zk
    broker -->|Metadata Lookup| zk

    style zk fill:#341f97,stroke:#222f3e,color:#fff
    style ctrl fill:#ff9f43,stroke:#ee5253,color:#000
    style broker fill:#2e86de,stroke:#0abde3,color:#fff
    style srv0 fill:#10ac84,stroke:#0f8f6b,color:#fff
    style srv1 fill:#10ac84,stroke:#0f8f6b,color:#fff
```

---

## 9. Ordered Startup Sequence

Unlike Deployments where all pods schedule concurrently, StatefulSets instantiate pods sequentially.

```mermaid
gantt
    title StatefulSet Startup Timeline (OrderedReady)
    dateFormat  X
    axisFormat %s

    section Pod: db-0
    Scheduling & Pulling    :active, 0, 5
    Init Containers Running  : 5, 8
    Main Container Booting   : 8, 12
    Liveness & Readiness Pass :crit, 12, 15

    section Pod: db-1
    Waiting for db-0 Ready   : 0, 15
    Scheduling & Pulling    :active, 15, 20
    Init Containers Running  : 20, 23
    Main Container Booting   : 23, 27
    Liveness & Readiness Pass :crit, 27, 30

    section Pod: db-2
    Waiting for db-1 Ready   : 0, 30
    Scheduling & Pulling    :active, 30, 35
```

---

## 10. Node Failure & Auto-Recovery

What happens when a node running a database node crashes?

```mermaid
graph TD
    subgraph "Physical Host Nodes"
        nodeA[Host Node A - CRASHED]
        nodeB[Host Node B - HEALTHY]
    end

    subgraph "Storage Area Network"
        disk[Cloud Persistent Disk<br/>pv-vol-02]
    end

    nodeA -->|1. Mount Broken| disk
    nodeB -->|3. Reschedule pod-1 & Attach| disk

    classDef crashed fill:#ffdddd,stroke:#ff5555,color:#000;
    classDef healthy fill:#ddffdd,stroke:#55ff55,color:#000;
    class nodeA crashed;
    class nodeB healthy;
```

---

## 11. Replica Synchronization Flow

The anatomy of a replicated write. Highlighting WAL committing and replication validation.

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Leader as Leader (postgres-0)
    participant WAL as Disk (Write-Ahead Log)
    participant Replica as Follower (postgres-1)

    Client->>Leader: 1. INSERT INTO users (name) VALUES ('Alice')
    Leader->>WAL: 2. Append Transaction Log to Disk
    Leader->>Replica: 3. Stream WAL Payload
    Replica->>Replica: 4. Apply WAL locally to storage
    Replica-->>Leader: 5. Replication Acknowledged
    Leader-->>Client: 6. Commit Successful
```

---

## 12. Stateful Application Lifecycle

A state machine showing the path of a stateful workload from creation to upgrade, downscaling, and volume decommissioning.

```mermaid
stateDiagram-v2
    [*] --> CreateStatefulSet
    CreateStatefulSet --> OrdinalInitialization : sequential boot (0 -> N-1)
    OrdinalInitialization --> ActiveSync : mount PVC & join consensus
    ActiveSync --> Running : Probes pass (Ready)

    state Running {
        [*] --> ReadWriteOperations
        ReadWriteOperations --> NodeMaintenance : Pod rescheduled
        NodeMaintenance --> MountOldVolume : Volume follows pod
        MountOldVolume --> ReplayWAL
        ReplayWAL --> ReadWriteOperations
    }

    Running --> ScaleDown : replicas reduced
    ScaleDown --> OrderlyTermination : terminate N-1 first
    OrderlyTermination --> VolumeRetained : PVC is kept intact
    VolumeRetained --> [*] : Requires manual delete

    Running --> RollingUpgrade : image updated
    RollingUpgrade --> ReverseRolling : update N-1 down to 0
```
