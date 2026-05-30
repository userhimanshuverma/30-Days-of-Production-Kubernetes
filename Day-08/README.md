# 📖 Day 08 — Persistent Volumes, Claims, & Storage Classes
### 🏷️ PHASE 2 — RUNNING REAL APPLICATIONS

Welcome to **Day 8** of the *30 Days of Production Kubernetes* course. Today, we bridge the gap between stateless compute and stateful storage. In this guide, we will answer the ultimate question once and for all: **How does Kubernetes keep your database data alive when pods can die at any millisecond?**

---

## 🗺️ The Core Architecture at a Glance

Before we dive deep, visualize the interaction between your applications, the Kubernetes API, and physical disks:

```
[ Pod (App Container) ]
       │ (Mounts Volume)
       ▼
[ PersistentVolumeClaim (PVC) ]  <--- Requested by Developer (Logical abstraction)
       │ (Binds to)
       ▼
[ PersistentVolume (PV) ]       <--- Managed by Platform / Provisioned Dynamically
       │ (Points to)
       ▼
[ Physical Storage / Cloud Disk ] (e.g., AWS EBS, GCP PD, Ceph, EFS)
```

---

## 1. Why Storage Is Hard in Kubernetes

In traditional infrastructure, a virtual machine (VM) has a local disk. If your database service crashes, the OS restarts it on the same VM, and the files are still there on `/var/lib/postgresql`.

Kubernetes breaks this paradigm:
1. **Pods are Temporary (Ephemeral)**: A Pod is designed to be destroyed and replaced. If a Node fails, the Kubernetes Scheduler reschedules the Pod on a completely different Node.
2. **Compute and Storage are Decoupled**: Since a Pod can run on Node-A now and Node-B tomorrow, local disk storage attached to Node-A is useless once the Pod moves to Node-B.
3. **Data Must Survive Pod Life Cycles**: Databases, caches, queues, and search engines require data to be *durable* and *consistent*, surviving restarts, node upgrades, and clusters resizes.

> [!IMPORTANT]
> In Kubernetes, **Compute (Pods)** and **Storage (Volumes)** have separate life cycles. A Pod must be able to claim storage, write to it, die, reappear on another node, and automatically mount the exact same storage volume with zero data loss.

---

## 2. The Kubernetes Storage Journey

The Kubernetes community experimented with several ways to solve the storage problem. Understanding this evolution helps you avoid using outdated, anti-pattern storage mechanisms in production.

### Step 1: `emptyDir` (Temporary Scratchpad)
* **What it is**: An empty directory created on the host node when a Pod starts.
* **Life Cycle**: Tied directly to the Pod. If the Pod is deleted, the data in `emptyDir` is **permanently destroyed**.
* **Use Cases**: Cache directories, compilation workspaces, or helper tools sharing files within the same Pod (e.g., sidecars).

### Step 2: `hostPath` (Node-Locked Storage)
* **What it is**: Mounts a specific file or directory from the host node's filesystem directly into the Pod.
* **The Problem**: If the Pod is rescheduled to another node, the data does not follow it. It remains on the previous node.
* **Use Cases**: System agents (like Prometheus Node Exporter or Fluentd) that *need* to read host metrics or logs. **Never use `hostPath` for database applications.**

### Step 3: Persistent Volumes (PV) & Claims (PVC)
* **What it is**: A clean separation of concerns.
  * **PersistentVolume (PV)**: A cluster-wide resource representing a piece of physical storage (e.g., a 100GB cloud disk). Built and managed by the cluster administrator or an automated controller.
  * **PersistentVolumeClaim (PVC)**: A request for storage by a developer (e.g., *"Give me 50GB of SSD storage"*).
* **Why it works**: The developer does not need to know which cloud provider is running underneath. They just request a PVC, and Kubernetes handles the mapping.

### Step 4: Dynamic Provisioning (StorageClasses)
* **What it is**: Instead of administrators manually creating 100 discrete PVs in advance (Static Provisioning), Kubernetes provisions them on-demand.
* **How it works**: When a developer creates a PVC, the cluster uses a `StorageClass` to communicate with the Cloud Provider API (AWS, GCP, Azure), automatically creates the physical disk, registers it as a `PV`, and attaches it to the Pod's node.

---

## 3. Persistent Volumes (PV) Deep Dive

A **PersistentVolume (PV)** is a physical storage resource in the cluster. It has a lifecycle independent of any individual Pod that uses it.

### Lifecycle of a PV
1. **Provisioning**: Can be *Static* (pre-created by admins) or *Dynamic* (generated on-demand by StorageClasses).
2. **Binding**: The control loop matches a PVC to an available PV that satisfies the size and access mode requirements, then binds them together. This is a 1-to-1 relationship.
3. **Using**: The Pod mounts the volume.
4. **Reclaiming**: What happens when the Pod/PVC is deleted? The PV's reclaim policy defines the next step:
   * `Retain`: The PV and its data remain intact. No other PVC can bind to it until an admin manually cleans it up. Safest for production.
   * `Delete`: The PV is deleted, and the physical disk in the cloud provider is destroyed automatically.
   * `Recycle` (Deprecated): Performs a basic scrub (`rm -rf *`) and makes the volume available again.

---

## 4. Persistent Volume Claims (PVC) Deep Dive

A **PersistentVolumeClaim (PVC)** is a developer's request for storage. Think of a Pod as a request for CPU/Memory, and a PVC as a request for Disk.

### Why do PVCs exist?
PVCs allow developers to build cloud-agnostic deployment files. A developer writes:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pg-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard-ssd
```
This YAML will work on AWS, GCP, Azure, or on-premise Ceph, as long as the cluster has a StorageClass named `standard-ssd`.

---

## 5. Storage Classes: Dynamic Storage Allocation

A `StorageClass` (SC) acts as a template for creating storage. It defines which driver (Provisioner) to use, what parameters to pass to the storage provider, and the billing/performance tier.

### Storage Tiers & Key Configuration Parameters:
* **Provisioner**: Tells Kubernetes which driver to use (e.g., `ebs.csi.aws.com` for AWS EBS).
* **VolumeBindingMode**:
  * `Immediate`: Provision the volume as soon as the PVC is created. (Warning: Can lead to scheduling errors if the disk is created in Zone-A but the scheduler places the Pod in Zone-B).
  * `WaitForFirstConsumer` (Recommended for production): Wait until a Pod is scheduled to a node before creating the volume. This guarantees the disk is provisioned in the same Availability Zone as the Pod.
* **AllowVolumeExpansion**: Set to `true` to allow live resizing of disks without deleting the PVC.

---

## 6. CSI (Container Storage Interface) Deep Dive

Historically, Kubernetes storage drivers were "in-tree"—meaning the code to talk to AWS EBS or Google Persistent Disk was compiled directly into the Kubernetes core binary. If AWS released a new EBS feature, users had to wait for a full Kubernetes version upgrade to use it.

To solve this, **CSI (Container Storage Interface)** was created. CSI is a standardized API that allows storage providers to write drivers *outside* the Kubernetes codebase.

### CSI Driver Components:
When you install a CSI driver (like AWS EBS CSI Driver), it runs several sidecar containers:
1. **external-provisioner**: Watches for PVC creation and calls the CSI driver's `CreateVolume` gRPC endpoint.
2. **external-attacher**: Watches for Pod scheduling and calls `ControllerPublishVolume` to attach the disk to the physical node.
3. **external-resizer**: Watches for PVC size updates and calls `ControllerExpandVolume`.
4. **node-driver-registrar**: Runs as a DaemonSet on every node to register the CSI driver local agent with the kubelet.
5. **CSI Node Driver**: Runs on every node, performs the actual OS mounts (`mount -t ext4 /dev/sdb /var/lib/kubelet/pods/...`).

---

## 7. Real Production Workloads Storage Patterns

Selecting the correct storage configuration is critical for databases and stateful applications:

### 🐘 PostgreSQL & MySQL (RDBMS)
* **Access Mode**: `ReadWriteOnce` (RWO) — Only one pod should write to a disk at a time to prevent corruption.
* **Storage Class**: High-IOPS block storage (SSD). Use `WaitForFirstConsumer` to align the disk zone with the Pod zone.
* **Reclaim Policy**: `Retain` (to prevent accidental delete disaster) or `Delete` if database replication handles node rebuilds.

### 🍃 MongoDB (Document Store)
* **Access Mode**: `ReadWriteOnce` (RWO).
* **Pattern**: Deploy as a `StatefulSet`. Each MongoDB replica set pod gets its own separate PVC and PV.
* **Performance**: Local SSDs via `local` volume types with Node Affinity can offer extremely low latency, but limit node rescheduling flexibility.

### 🔍 Elasticsearch / OpenSearch (Search Engine)
* **Storage Pattern**: Uses large amounts of index data. Elasticsearch does its own application-level replication.
* **Optimization**: Use high-performance NVMe instance storage or network-attached SSDs with high IOPS throughput.

### 🪵 Apache Kafka (Message Queue)
* **Storage Pattern**: Sequential write-heavy logs.
* **Execution**: Deploy using a StatefulSet. Set up distinct directories for disk volumes. Since Kafka manages data replication across brokers, standard high-throughput block disks are optimal.

### 🧠 Machine Learning & Data Science (ML Workloads)
* **Access Mode**: `ReadWriteMany` (RWX) or `ReadOnlyMany` (ROX).
* **Pattern**: Multiple worker Pods (e.g., training models) need to read the same massive dataset simultaneously.
* **Implementation**: Use Shared Filesystems like AWS EFS, Google Filestore, CephFS, or object store gateways (S3-mounters).

---

## 📂 Day 08 Repository Structure

Explore the dedicated directories to master Persistent Storage:

* 📊 **[diagrams/README.md](file:///d:/30_Days_of_Production_Kubernetes/Day-08/diagrams/README.md)**: 12 comprehensive Mermaid architecture and lifecycle diagrams.
* 📝 **[core-concepts.md](file:///d:/30_Days_of_Production_Kubernetes/Day-08/notes/core-concepts.md)**: Core definitions, state machine states, and CSI specifications.
* ⚡ **[lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-08/production-notes/lessons-learned.md)**: Real-world gotchas, IOPS limitations, zone bindings, and DB performance tuning.
* 🚨 **[playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-08/troubleshooting/playbook.md)**: Practical scenarios covering MountVolume failures, Pending PVCs, and CSI issues.
* 🛠️ **[lab-guide.md](file:///d:/30_Days_of_Production_Kubernetes/Day-08/labs/lab-guide.md)**: Hands-on labs covering manual local mounts, dynamic gp3 provisioning, and volume expansions.
* 📄 **[manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-08/manifests/)**: Production-ready YAML files for PVs, PVCs, StorageClasses, and StatefulSets.
* 🎮 **[kubernetes-storage-simulator.html](file:///d:/30_Days_of_Production_Kubernetes/Day-08/resources/kubernetes-storage-simulator.html)**: Futuristic dashboard visual simulator representing the entire Kubernetes storage pipeline.
* 🏆 **[challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-08/exercises/challenges.md)**: Scenario challenges to test your understanding of storage topologies.

