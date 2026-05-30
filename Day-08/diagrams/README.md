# 📊 Day 08 — Storage Architecture Diagrams

This document contains 12 professional-grade Mermaid diagrams designed to visualize how Kubernetes decouples compute from storage, manages lifecycle transitions, coordinates with CSI drivers, and ensures high availability for stateful workloads.

---

## 1. Pod → PVC → PV Binding Workflow
This diagram illustrates the logical separation of concerns. The developer only interacts with the Pod and the PVC, while the cluster maps them to a PV and the underlying physical disk.

```mermaid
graph TD
    subgraph DeveloperSpace ["Developer Domain (Namespaced)"]
        Pod["Pod: postgres-0"]
        PVC["PersistentVolumeClaim: pg-data-postgres-0"]
    end

    subgraph AdminSpace ["Cluster Infrastructure (Cluster-Scoped)"]
        PV["PersistentVolume: pv-ebs-vol-08f2e9"]
        CloudDisk[("Physical Cloud Disk: AWS EBS gp3")]
    end

    Pod -->|1. Mounts volume 'pg-storage'| PVC
    PVC -->|2. Logically binds to (1:1)| PV
    PV -->|3. References physical volume ID| CloudDisk
    
    style Pod fill:#8a2be2,stroke:#fff,stroke-width:2px,color:#fff
    style PVC fill:#a982ed,stroke:#fff,stroke-width:2px,color:#fff
    style PV fill:#4b0082,stroke:#fff,stroke-width:2px,color:#fff
    style CloudDisk fill:#2f4f4f,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 2. Storage Class Dynamic Provisioning Architecture
The StorageClass acts as a "factory blueprint". When a claim requests a StorageClass, it triggers the provisioner to automatically build the PV.

```mermaid
graph LR
    PVC["Developer Claim: PVC"] -->|Requests StorageClass: gp3| SC["StorageClass: gp3"]
    SC -->|1. Invokes Provisioner| Prov["CSI Driver Provisioner"]
    Prov -->|2. Creates Volume| CloudAPI["Cloud Storage API"]
    CloudAPI -->|3. Returns Volume ID| Prov
    Prov -->|4. Registers Resource| PV["New PersistentVolume"]
    PV -->|5. Binds 1:1| PVC
    
    style PVC fill:#a982ed,stroke:#fff,color:#fff
    style SC fill:#9400d3,stroke:#fff,color:#fff
    style Prov fill:#4b0082,stroke:#fff,color:#fff
    style CloudAPI fill:#2f4f4f,stroke:#fff,color:#fff
    style PV fill:#8a2be2,stroke:#fff,color:#fff
```

---

## 3. CSI Component Architecture
The Container Storage Interface (CSI) separates Kubernetes core logic from cloud-specific driver code. It utilizes sidecar containers to bridge K8s events with the storage driver.

```mermaid
graph TD
    subgraph K8sControlPlane ["Kubernetes Control Plane"]
        APIServer["kube-apiserver"]
        K8sPVController["PV Controller"]
    end

    subgraph CSISidecars ["CSI Controller Pod (Deployment)"]
        ExtProvisioner["external-provisioner"]
        ExtAttacher["external-attacher"]
        ExtResizer["external-resizer"]
        CSIDriverController["CSI Controller Plugin"]
    end

    subgraph K8sNode ["Worker Node"]
        Kubelet["kubelet"]
        NodeRegistrar["node-driver-registrar"]
        CSIDriverNode["CSI Node Plugin"]
    end

    APIServer <--> K8sPVController
    APIServer <-- Watches PVC/PV --> ExtProvisioner
    APIServer <-- Watches VolumeAttachment --> ExtAttacher
    APIServer <-- Watches PVC Resize --> ExtResizer

    ExtProvisioner -->|gRPC: CreateVolume| CSIDriverController
    ExtAttacher -->|gRPC: ControllerPublish| CSIDriverController
    ExtResizer -->|gRPC: ControllerExpand| CSIDriverController

    NodeRegistrar -->|gRPC: GetInfo| CSIDriverNode
    NodeRegistrar -->|Registers Driver| Kubelet
    Kubelet -->|gRPC: NodeStage/Publish| CSIDriverNode
    
    style APIServer fill:#4b0082,stroke:#fff,color:#fff
    style CSIDriverController fill:#8a2be2,stroke:#fff,color:#fff
    style CSIDriverNode fill:#8a2be2,stroke:#fff,color:#fff
    style Kubelet fill:#2f4f4f,stroke:#fff,color:#fff
```

---

## 4. Dynamic Provisioning Sequence Flow
This step-by-step sequence diagram shows what happens when a developer applies a PVC file to a cluster with dynamic provisioning.

```mermaid
sequenceDiagram
    autonumber
    actor Developer
    participant K8s as Kubernetes API
    participant Sidecar as CSI external-provisioner
    participant Cloud as Cloud Provider Storage API
    participant PV_Ctrl as PV Controller
    participant Kubelet as Node Kubelet
    
    Developer->>K8s: kubectl apply -f pvc.yaml (StorageClass: gp3)
    K8s->>Sidecar: PVC Created event
    Sidecar->>Cloud: gRPC CreateVolume() -> Provision Disk
    Cloud-->>Sidecar: Disk Provisioned successfully (Disk ID: vol-12345)
    Sidecar->>K8s: Create PV resource (spec.volumeID = vol-12345)
    PV_Ctrl->>K8s: Bind PVC <-> PV (Status: Bound)
    
    Note over Developer, Kubelet: Pod Scheduling & Attachment
    
    Developer->>K8s: kubectl apply -f pod.yaml (references PVC)
    K8s->>Kubelet: Schedule Pod to Node-A
    Kubelet->>Cloud: Attach Disk vol-12345 to Node-A
    Kubelet->>Kubelet: Mount Disk to /var/lib/kubelet/pods/...
    Kubelet->>Developer: Pod status -> Running
```

---

## 5. Volume Attachment Lifecycle
This state diagram represents the lifecycle states of a volume, from creation to final clean-up.

```mermaid
stateDiagram-v2
    [*] --> Provisioning : PVC Created
    Provisioning --> Available : PV Created
    Available --> Bound : PVC-PV Linked
    Bound --> Attaching : Pod Scheduled to Node
    Attaching --> Attached : Disk Mapped to Node (ControllerPublish)
    Attached --> Mounting : Kubelet Prepares Filesystem (NodeStage)
    Mounting --> Mounted : Mount to Container Directory (NodePublish)
    Mounted --> InUse : Pod Container Running
    InUse --> Unmounting : Pod Terminated
    Unmounting --> Unmounted : Removed from Container Dir (NodeUnpublish)
    Unmounted --> Detaching : Released from Node (ControllerUnpublish)
    Detaching --> Released : PVC Deleted
    Released --> Deleting : ReclaimPolicy: Delete
    Released --> Retained : ReclaimPolicy: Retain
    Deleting --> [*] : Physical Disk Destroyed
    Retained --> [*] : Awaiting Admin Clean-up
```

---

## 6. Stateful Application Architecture
StatefulSets ensure each pod maintains a stable ordinal identifier (`-0`, `-1`, `-2`) mapped to a dedicated PVC and PV. If `postgres-1` dies, it mounts the exact same `pvc-1` when rescheduled.

```mermaid
graph TD
    subgraph HeadlessService ["Headless Service: postgres-db"]
        DB-DNS-0["postgres-0.postgres-db.default.svc.cluster.local"]
        DB-DNS-1["postgres-1.postgres-db.default.svc.cluster.local"]
    end

    subgraph StatefulSetPods ["StatefulSet: postgres"]
        Pod0["Pod: postgres-0"]
        Pod1["Pod: postgres-1"]
    end

    subgraph Claims ["Persistent Volume Claims"]
        PVC0["PVC: pg-data-postgres-0"]
        PVC1["PVC: pg-data-postgres-1"]
    end

    subgraph Volumes ["Persistent Volumes"]
        PV0["PV: pv-vol-0"]
        PV1["PV: pv-vol-1"]
    end

    Pod0 <--> DB-DNS-0
    Pod1 <--> DB-DNS-1

    Pod0 --> PVC0
    Pod1 --> PVC1

    PVC0 --> PV0
    PVC1 --> PV1
    
    style Pod0 fill:#8a2be2,stroke:#fff,color:#fff
    style Pod1 fill:#8a2be2,stroke:#fff,color:#fff
    style PVC0 fill:#a982ed,stroke:#fff,color:#fff
    style PVC1 fill:#a982ed,stroke:#fff,color:#fff
    style PV0 fill:#4b0082,stroke:#fff,color:#fff
    style PV1 fill:#4b0082,stroke:#fff,color:#fff
```

---

## 7. Multi-Zone Storage Architecture
This diagram contrasts the impact of `volumeBindingMode: Immediate` (bad) versus `WaitForFirstConsumer` (good).

```mermaid
graph TD
    subgraph Zone-A ["Availability Zone: us-east-1a"]
        NodeA["Worker Node-A"]
        PodA["Pod: my-db"]
        PVA["PV: Disk in Zone-A"]
    end

    subgraph Zone-B ["Availability Zone: us-east-1b"]
        NodeB["Worker Node-B"]
        PVB["PV: Mismatched Disk in Zone-B"]
    end

    subgraph SC_Modes ["Storage Class Binding Modes"]
        Immediate["volumeBindingMode: Immediate - Creates PV anywhere, e.g. Zone-B. Pod cannot schedule because Node-A has resource constraints!"]
        WaitForFirst["volumeBindingMode: WaitForFirstConsumer - Scheduler selects Node-A first. StorageClass then creates PV in Zone-A."]
    end

    PodA -->|Requires Mount| PVA
    NodeA -->|Runs| PodA
    
    style Zone-A fill:#2f4f4f,stroke:#fff,color:#fff
    style Zone-B fill:#1c1c1c,stroke:#fff,color:#fff
    style Immediate fill:#8b0000,stroke:#fff,color:#fff
    style WaitForFirst fill:#006400,stroke:#fff,color:#fff
```

---

## 8. Database Storage Write Path
Illustrates the layers a write operation undergoes in a Kubernetes Pod running a transactional database before hitting non-volatile media.

```mermaid
graph TD
    App["Database App Container"] -->|1. Write SQL Statement| WAL["Write-Ahead Log / Page Cache"]
    WAL -->|2. OS Cache Buffer| KubeMount["Container Mount: /var/lib/postgresql/data"]
    KubeMount -->|3. Kubelet Loop device/Direct map| NodeMount["Node Host Mount: /var/lib/kubelet/..."]
    NodeMount -->|4. CSI Driver Protocol| NetworkStorage["Network Fabric / SAN Controller"]
    NetworkStorage -->|5. fsync() write confirmation| DiskController["Physical NVMe/SSD Disk Controller"]
    
    style App fill:#8a2be2,stroke:#fff,color:#fff
    style WAL fill:#9400d3,stroke:#fff,color:#fff
    style DiskController fill:#2f4f4f,stroke:#fff,color:#fff
```

---

## 9. Storage Node Failure & Recovery Flow
When a node becomes unhealthy, Kubernetes must migrate stateful workloads safely. Since block storage is ReadWriteOnce, force evictions require clean volume disassociations.

```mermaid
sequenceDiagram
    Node-A->>K8s API: [Node Unreachable / Heartbeat Lost]
    K8s API->>K8s API: Mark Node-A as Unhealthy (NotReady)
    K8s API->>Scheduler: Evict database Pod from Node-A
    Scheduler->>K8s API: Schedule database Pod to Node-B
    K8s API->>CSI Attacher: Call ControllerUnpublish (Force detach vol-12345 from Node-A)
    CSI Attacher->>Cloud API: Detach Disk vol-12345
    Cloud API-->>CSI Attacher: Disk Detached
    CSI Attacher->>Cloud API: Attach Disk vol-12345 to Node-B
    Cloud API-->>CSI Attacher: Disk Attached
    K8s API->>Kubelet Node-B: Mount & start Pod
```

---

## 10. Backup and Restore Architecture
Using custom Volume Snapshots, developers can request point-in-time copies of their production volumes directly via the Kubernetes API.

```mermaid
graph TD
    subgraph BackupFlow ["Volume Backup"]
        PVC["PersistentVolumeClaim"] -->|Backs up| VS["VolumeSnapshot"]
        VS -->|Instantiates| VSC["VolumeSnapshotClass"]
        VSC -->|Triggers| VSContent["VolumeSnapshotContent"]
        VSContent -->|Saves backup| CloudSnap["Cloud Provider Snapshots"]
    end

    subgraph RestoreFlow ["Volume Restore"]
        NewPVC["New PersistentVolumeClaim"] -->|Restores from source| VS
        NewPVC -->|Triggers provisioning| NewPV["New PersistentVolume"]
        NewPV -->|Linked to new| NewCloudDisk[("New Disk restored from snapshot")]
    end
    
    style VS fill:#8a2be2,stroke:#fff,color:#fff
    style CloudSnap fill:#2f4f4f,stroke:#fff,color:#fff
    style NewPVC fill:#a982ed,stroke:#fff,color:#fff
    style NewCloudDisk fill:#2f4f4f,stroke:#fff,color:#fff
```

---

## 11. CSI Driver gRPC Interaction Sequence
This sequence details the low-level gRPC calls made by Kubernetes sidecars and Kubelets to the CSI driver during volume lifecycle changes.

```mermaid
sequenceDiagram
    participant K8s as K8s PV Controller / Kubelet
    participant CSI as CSI Driver gRPC Interface
    participant OS as Node OS System Tools
    
    K8s->>CSI: CreateVolume() [Request size & topology]
    CSI-->>K8s: CreateVolumeResponse [Volume ID & topology parameters]
    
    Note over K8s, CSI: Attach Volume to Node
    K8s->>CSI: ControllerPublishVolume() [Attach disk to host node]
    CSI-->>K8s: ControllerPublishVolumeResponse [Device path on node]
    
    Note over K8s, OS: Stage & Mount (Kubelet Node execution)
    K8s->>CSI: NodeStageVolume() [Format device with filesystem, e.g., ext4]
    CSI->>OS: mkfs.ext4 /dev/xvdb & mount to global directory
    CSI-->>K8s: NodeStageVolumeResponse
    
    K8s->>CSI: NodePublishVolume() [Bind mount from global dir to Pod dir]
    CSI->>OS: mount --bind /global/dir /var/lib/kubelet/pods/pod-id/volumes/...
    CSI-->>K8s: NodePublishVolumeResponse
```

---

## 12. Persistent Storage Lifecycle State Machine
A PersistentVolume cycles through several phases during its lifecycle. This state machine demonstrates the transitions and policies.

```mermaid
stateDiagram-v2
    [*] --> Available : PV Created
    Available --> Bound : PVC claims the PV
    Bound --> Released : PVC is deleted by user
    Released --> Retained : ReclaimPolicy = Retain
    Released --> Deleted : ReclaimPolicy = Delete
    Released --> Failed : Cleanup execution failure
    
    Retained --> Available : Manual admin intervention (clean & reset)
    Deleted --> [*] : Backing physical resource destroyed
    Failed --> Available : Admin debugged & resolved filesystem issues
```
