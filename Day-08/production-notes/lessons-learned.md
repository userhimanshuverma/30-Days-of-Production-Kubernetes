# ⚡ Day 08 Production Notes — Lessons Learned Running Databases on Kubernetes

This guide summarizes real-world operational challenges, performance bottlenecks, and design patterns compiled from running high-throughput database workloads (PostgreSQL, Kafka, Elasticsearch) on production Kubernetes clusters.

---

## 1. Storage Performance: IOPS & Throughput Bottlenecks

A common failure mode in cloud environments is running out of disk performance credits, causing applications to stall, miss health checks, and cascade into crash loops.

### SSD (gp3, gp2) vs HDD (st1) Tradeoffs
* **Avoid gp2**: On AWS, `gp2` volumes scale IOPS linearly with capacity. A small 10Gi volume gets only 100 IOPS (with burst capability up to 3,000). Once burst credits expire, disk I/O latency spikes to seconds, freezing databases.
* **Standardize on gp3**: AWS `gp3` separates size from performance. You get 3,000 IOPS and 125 MB/s throughput baseline regardless of volume size. You can scale IOPS separately if database queries require higher random read/write throughput.
* **HDD for Logging/Backup Only**: Do not host transactional databases (Postgres, MySQL) on HDDs. Use HDDs (`st1`, `sc1`) strictly for sequential workloads like backup dumps or cold storage search indexes.

### Ephemeral Storage vs Persistent Storage
For extreme low-latency performance (e.g. ScyllaDB, high-volume Redis clusters), network-attached cloud storage (EBS gp3) adds latency overhead.
* **Solution**: Use **Instance Store (NVMe SSDs)** via the Kubernetes `local` volume type.
* **Tradeoff**: Instance store data is lost if the host node is terminated. Ensure your application handles replication at the software layer (e.g., Elasticsearch replicas, Cassandra replica factors).

---

## 2. The Multi-Zone Scheduling Nightmare

In multi-zone clusters (e.g., `us-east-1a`, `us-east-1b`, `us-east-1c`), network-attached block volumes (AWS EBS, GCP PD) **cannot bridge zones**. An EBS volume in `us-east-1a` cannot be attached to a node in `us-east-1b`.

### The Anti-Pattern
If your StorageClass uses `volumeBindingMode: Immediate`, creating a PVC triggers the cloud provider to provision the physical volume immediately. If the volume is created in `us-east-1b`, but your cluster's available CPU/Memory resources are only in `us-east-1a`, the Pod will schedule to `us-east-1a` and fail to start with a `VolumeNodeAffinity` mismatch error.

### The Production Pattern
Always use `volumeBindingMode: WaitForFirstConsumer` for block storage.
```yaml
volumeBindingMode: WaitForFirstConsumer
```
This forces the Kubernetes Scheduler to select a node for the Pod *first* (based on CPU, memory, taint, and toleration rules). Once the node is selected, the CSI driver provisions the volume in the **same availability zone** as that host node.

---

## 3. Volume Expansion Realities

Modern Kubernetes CSI drivers support live volume expansion. This allows you to increase a volume's capacity (e.g., 20Gi to 50Gi) without deleting the PVC.

> [!IMPORTANT]
> - **Read-Only Operation**: You can increase volume size, but you **can never decrease it**. Cloud providers do not support shrinking block storage.
> - **In-Use Resizing**: Most modern drivers allow online expansion. However, the OS filesystem expansion (`resize2fs` or `xfs_growfs`) only triggers when the Pod is actively running and using the volume.
> - **Throttling**: Cloud providers limit how frequently you can resize a volume. For instance, AWS EBS restricts volume modification to once every 6 hours.

---

## 4. Disaster Recovery & Backup Strategies

Never rely on PV durability as your sole backup strategy. Cloud providers guarantee durability, but they do not prevent user error (e.g., `DROP DATABASE`).

### Volume Snapshots
Kubernetes provides standard resources to manage snapshots:
* `VolumeSnapshotClass`: Defines the driver and parameter rules.
* `VolumeSnapshot`: The user's request to capture a point-in-time state.
* `VolumeSnapshotContent`: The actual cluster resource pointing to the physical cloud snapshot.

### Velero: The Cluster Backup Engine
Use tools like **Velero** to automate backup workflows:
* Velero hooks into the K8s API, saves resource definitions (Deployments, Secrets, PVCs) to object storage (S3), and uses CSI volume snapshots to back up underlying data blocks.
* In disaster recovery, Velero recreates the namespace, recovers the PVCs, provisions the disks from the snapshots, and mounts them back to the restored pods.

---

## 5. Senior-Level Operational Cheat Sheet

* **Mount Propagation**: When using containerized services that mount directories (like Docker-in-Docker or volume mounts), set `mountPropagation: Bidirectional` so the container can share mounts with the host.
* **Disk Corruption and fsync**: Ensure databases are configured to write using `fsync`. Unclean Pod terminations on local storage can corrupt database filesystems if write caches aren't properly flushed.
* **PV Deletion Protection**: Enable the `kubernetes.io/pvc-protection` finalizer. This prevents PVC deletion if a Pod is actively using the volume.
* **Storage Cost Allocation**: Tag your StorageClasses. Ensure cloud provider tagging is enabled so you can track storage spend per environment (dev vs production) and department.
