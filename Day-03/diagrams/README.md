# 📊 Day 3 Architecture Diagrams — Kubernetes Internals

This document compiles the 12 primary architectural diagrams and flowcharts that demystify the internal workings of a production-grade Kubernetes cluster.

---

## 1. Complete Kubernetes Architecture
This diagram outlines the segregation between the Control Plane (managing state, scheduling, and orchestrating) and the Data Plane (executing container workloads).

```mermaid
graph TB
    subgraph "Control Plane (Master Nodes)"
        direction TB
        apiserver["kube-apiserver<br/>(Stateless REST API gateway)"]
        etcd["etcd cluster<br/>(Consistent, distributed storage)"]
        scheduler["kube-scheduler<br/>(Workload placement scheduler)"]
        kcm["kube-controller-manager<br/>(Reconciliation controllers daemon)"]
        ccm["cloud-controller-manager<br/>(Cloud infrastructure mapper)"]
        
        apiserver <--> etcd
        scheduler --> apiserver
        kcm --> apiserver
        ccm --> apiserver
    end

    subgraph "Data Plane (Worker Nodes)"
        direction LR
        subgraph "Node A"
            kubelet_a["kubelet (Node Agent)"]
            proxy_a["kube-proxy (Service Router)"]
            cri_a["CRI (containerd/CRI-O)"]
            pod_a["Pod 1"]
            pod_b["Pod 2"]
            
            kubelet_a <--> cri_a
            cri_a --> pod_a
            cri_a --> pod_b
        end
        subgraph "Node B"
            kubelet_b["kubelet (Node Agent)"]
            proxy_b["kube-proxy (Service Router)"]
            cri_b["CRI (containerd/CRI-O)"]
            pod_c["Pod 3"]
            
            kubelet_b <--> cri_b
            cri_b --> pod_c
        end
    end

    client["kubectl / API Clients"] --> apiserver
    kubelet_a --> apiserver
    kubelet_b --> apiserver
    proxy_a --> apiserver
    proxy_b --> apiserver
```

---

## 2. Control Plane Components Internal Communication
In Kubernetes, **no component talks to etcd directly except the API Server**, and components **never** communicate directly with one another. All communication happens asynchronously via the API Server.

```mermaid
graph LR
    etcd[(etcd Database)] <--> apiserver((kube-apiserver))
    
    subgraph "Control Plane Clients"
        scheduler(kube-scheduler) -->|Watch & Bind| apiserver
        kcm(kube-controller-manager) -->|Watch & Update| apiserver
        ccm(cloud-controller-manager) -->|Watch & Update| apiserver
    end

    subgraph "Worker Node Clients"
        kubelet(kubelet) -->|Watch & Status Patch| apiserver
        proxy(kube-proxy) -->|Watch Services/Endpoints| apiserver
    end
    
    style apiserver fill:#8a2be2,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 3. Worker Node Internals & Runtime Interface Layers
The Kubelet orchestrates runtime, storage, and networking layers through standardised gRPC sockets (CRI, CNI, CSI).

```mermaid
graph TD
    apiserver((kube-apiserver)) <-->|Pod Spec Watch & Status Patch| kubelet[kubelet Node Agent]
    
    subgraph "Kubelet Pluggable Interfaces (gRPC sockets)"
        kubelet <-->|CRI gRPC| cri[Container Runtime Interface<br/>e.g., containerd / CRI-O]
        kubelet <-->|CSI gRPC| csi[Container Storage Interface<br/>e.g., EBS / Ceph plugin]
        cri <-->|CNI gRPC| cni[Container Network Interface<br/>e.g., Calico / Cilium]
    end
    
    subgraph "Operating System Kernel"
        network[Veth Pairs, Routing Tables]
        storage[Mounted Volumes, Mount namespaces]
    end

    cni --> network
    csi --> storage
    cri -->|Spawns| containers[Application Containers]
```

---

## 4. API Request Lifecycle
Every request arriving at the API Server must pass through three distinct phases: **Authentication**, **Authorization**, and **Admission Control** before it can be committed to etcd.

```mermaid
flowchart TD
    req([Incoming REST Request]) --> handler[HTTP Handler]
    
    subgraph "1. Authentication (AuthN)"
        handler --> cert[Client Certificate?]
        handler --> token[JWT / ServiceAccount Token?]
        handler --> web[Webhook Auth?]
        cert -->|Fail| deny([401 Unauthorized])
        token -->|Fail| deny
        web -->|Fail| deny
    end
    
    subgraph "2. Authorization (AuthZ)"
        cert -->|Pass| rbac[RBAC Assessment]
        token -->|Pass| rbac
        web -->|Pass| rbac
        rbac -->|No Match| forbid([403 Forbidden])
    end
    
    subgraph "3. Admission Controllers"
        rbac -->|Pass| mut[Mutating Webhooks]
        mut -->|Mutate Spec| val_schema[Schema & Syntax Validation]
        val_schema -->|Invalid JSON/YAML| badreq([400 Bad Request])
        val_schema -->|Valid| val_admit[Validating Webhooks]
        val_admit -->|Policy Violation| deny_admit([403 Policy Blocked])
    end

    val_admit -->|Pass| db[(etcd Write)]
    db --> response([201 Created / 200 OK])
```

---

## 5. Scheduler Filtering & Scoring Workflow
The scheduling cycle resolves which physical node is the optimal host for a Pod. It evaluates nodes using predicates (filtering) and priorities (scoring).

```mermaid
flowchart TD
    queue[Unscheduled Pod Queue] --> select[Pick Pod from Queue]
    
    subgraph "Phase 1: Filtering (Predicates)"
        select --> fit_resources[Node Resources Available? CPU/Mem]
        fit_resources -->|No| drop[Discard Node]
        fit_resources -->|Yes| fit_selector[Node Selector / Affinity Match?]
        fit_selector -->|No| drop
        fit_selector -->|Yes| fit_ports[Node Port Conflict?]
        fit_ports -->|No| fit_taints[Taint & Toleration Check]
        fit_ports -->|Yes| drop
        fit_taints -->|Mismatch| drop
    end

    subgraph "Phase 2: Scoring (Priorities)"
        fit_taints -->|Pass| score_affinity[Node Affinity Scoring]
        score_affinity --> score_images[Image Locality - Is image already pulled?]
        score_images --> score_spread[Topology Spread - Balance across zones]
        score_spread --> sum[Sum Weighted Scores 0-100]
    end

    sum --> bind[Select Node with Highest Score]
    bind --> bind_api[Write Binding object back to API Server]
```

---

## 6. Controller Manager Reconciliation Loop
Controllers run a continuous control loop (the reconciliation loop) to drive the actual state of the cluster toward the desired state.

```mermaid
stateDiagram-v2
    [*] --> StartLoop
    StartLoop --> ObserveActualState : Query Informer Cache
    ObserveActualState --> ReadDesiredState : Query API Server Spec
    ReadDesiredState --> CompareStates : Calculate Delta
    
    CompareStates --> NoDelta : Desired == Actual
    NoDelta --> Sleep : Wait for Event
    
    CompareStates --> HasDelta : Desired != Actual
    HasDelta --> CreateActions : e.g., Scale Up/Down Pods
    CreateActions --> ExecuteActions : API Write Request
    ExecuteActions --> ObserveActualState
    
    Sleep --> StartLoop : Triggered by Reflector Watch
```

---

## 7. etcd Storage, Consensus & Write Flow
Because etcd is a distributed consensus database, writes must be replicated and committed across a quorum of nodes via Raft before returning success.

```mermaid
sequenceDiagram
    autonumber
    participant AP as API Server
    participant L as etcd Leader
    participant F1 as etcd Follower 1
    participant F2 as etcd Follower 2
    participant D as Disk (WAL & Snapshot)

    AP->>L: HTTP POST Write Request
    Note over L: Append to local WAL (Write-Ahead Log)
    L->>F1: Raft AppendEntries (Replicate Log)
    L->>F2: Raft AppendEntries (Replicate Log)
    F1->>F1: Write to local WAL & memory
    F2->>F2: Write to local WAL & memory
    F1-->>L: AppendEntries Response (Acknowledge)
    F2-->>L: AppendEntries Response (Acknowledge)
    Note over L: Quorum Reached (2/3 nodes acknowledged)
    L->>D: Commit log entry to disk DB (B-Tree/B+ Tree)
    L->>F1: Commit Instruction
    L->>F2: Commit Instruction
    L-->>AP: 201 Success Response
```

---

## 8. kubelet Pod Sync Loop
The kubelet runs a sync loop (`syncLoop`) that consumes configurations from three sources: the API Server, local files, and an HTTP endpoint. It acts as the local node supervisor.

```mermaid
flowchart TD
    api[kube-apiserver Watch] --> queue[Sync Loop Queue]
    file[Local Files /etc/kubernetes/manifests] --> queue
    http[HTTP Endpoint] --> queue
    
    queue --> pick[Pick Pod Event]
    pick --> verify[Verify Resources & Sandboxes]
    verify --> prepare[CSI Volume Mounting]
    prepare --> cri_sandbox[CRI: Create Pod Sandbox / Network Namespace]
    cri_sandbox --> cni_network[CNI: Configure IP & Routes]
    cni_network --> cri_pull[CRI: Pull Container Image]
    cri_pull --> cri_run[CRI: Start Application Container]
    cri_run --> probe[Liveness / Readiness Probe Watchers Start]
```

---

## 9. Service Networking Flow (kube-proxy)
kube-proxy implements virtual IP addresses for Services via user-space routing or Linux kernel capabilities (iptables/IPVS).

```mermaid
flowchart TD
    Client[Pod or External Client] -->|Traffic to ClusterIP 10.96.0.10:80| Interface[Node NIC]
    Interface --> Kernel[Linux Kernel Netfilter]
    
    subgraph "kube-proxy Engine (watches API Server)"
        kp[kube-proxy Daemon] -->|Generates routing table rules| rules[IPVS Tables / IPTables Chains]
    end
    
    Kernel -->|Lookup matched rule| rules
    rules -->|DNAT - Destination NAT translation| route[Translate to actual Pod IP e.g., 10.244.1.4:8080]
    route --> Outflow[Send Packet to Pod]
```

---

## 10. Pod Deployment Lifecycle (End-to-End)
An end-to-end look at the stages of a workload deployment, showing how the control plane and worker node work in tandem.

```mermaid
sequenceDiagram
    autonumber
    Platform Engineer->>kubectl: kubectl apply -f deployment.yaml
    kubectl->>kube-apiserver: POST Deployment Spec
    kube-apiserver->>etcd: Persist Deployment Object
    Note over kube-controller-manager: Deployment Controller watches Event
    kube-controller-manager->>kube-apiserver: POST ReplicaSet Spec
    kube-apiserver->>etcd: Persist ReplicaSet Object
    Note over kube-controller-manager: ReplicaSet Controller watches Event
    kube-controller-manager->>kube-apiserver: POST 3 Pod Specs (Pending Node)
    kube-apiserver->>etcd: Persist Pod Objects
    Note over kube-scheduler: Scheduler watches Pending Pods
    kube-scheduler->>kube-apiserver: POST Binding (Pod 1 -> Node A)
    kube-apiserver->>etcd: Update Pod Spec (nodeName=NodeA)
    Note over kubelet (Node A): Kubelet watches pods for Node A
    kubelet (Node A)->>containerd: gRPC RunPodSandbox & StartContainer
    kubelet (Node A)->>kube-apiserver: PATCH Pod Status -> Running
    kube-apiserver->>etcd: Update Pod Status
    Note over kube-proxy (All Nodes): Kube-proxy watches Services & Pods
    kube-proxy (All Nodes)->>OS Kernel: Update iptables/IPVS to route to new Pod IP
```

---

## 11. Cluster State Reconciliation
A simplified diagram explaining the core architectural concept of Desired State vs. Actual State reconciliation loop.

```mermaid
graph TD
    desired[Desired State<br/>Stored in etcd<br/>e.g., replicas: 3]
    actual[Actual State<br/>Running in cluster nodes<br/>e.g., replicas: 1]
    
    subgraph "Reconciliation Process"
        diff[Identify Delta<br/>replicas difference = +2]
        action[Trigger Action<br/>Create 2 Pod instances]
    end

    desired -->|Read Spec| diff
    actual -->|Query Pod Cache| diff
    diff --> action
    action -->|Apply modifications| actual
    
    style desired fill:#4b0082,stroke:#fff,color:#fff
    style actual fill:#1e90ff,stroke:#fff,color:#fff
    style diff fill:#8a2be2,stroke:#fff,color:#fff
```

---

## 12. High Availability (HA) Control Plane Topology
A production-grade, highly available multi-master topology configuration.

```mermaid
graph TD
    Client[Client / kubectl / Nodes] --> LB[External Load Balancer<br/>e.g., F5 / HAProxy / NGINX]
    
    subgraph "Master Node 1"
        api1[kube-apiserver 1]
        kcm1[kube-controller-manager 1<br/>Passive - Standby]
        sched1[kube-scheduler 1<br/>Passive - Standby]
        etcd1[etcd Node 1]
    end

    subgraph "Master Node 2"
        api2[kube-apiserver 2]
        kcm2[kube-controller-manager 2<br/>Active - Leader]
        sched2[kube-scheduler 2<br/>Active - Leader]
        etcd2[etcd Node 2]
    end

    subgraph "Master Node 3"
        api3[kube-apiserver 3]
        kcm3[kube-controller-manager 3<br/>Passive - Standby]
        sched3[kube-scheduler 3<br/>Passive - Standby]
        etcd3[etcd Node 3]
    end

    LB -->|Load balances stateless REST traffic| api1
    LB -->|Load balances stateless REST traffic| api2
    LB -->|Load balances stateless REST traffic| api3

    api1 <--> etcd1
    api2 <--> etcd2
    api3 <--> etcd3
    
    etcd1 <-->|Raft Consensus Replication| etcd2
    etcd2 <-->|Raft Consensus Replication| etcd3
    etcd3 <-->|Raft Consensus Replication| etcd1

    kcm2 -->|Acquired lease lock in etcd| api2
    sched2 -->|Acquired lease lock in etcd| api2
```
