# 📝 Day 08 Core Concepts — Kubernetes Storage Architecture

This document provides an architect-level deep dive into the Kubernetes volume subsystem, details the Container Storage Interface (CSI) specification, and explains how stateful identities are managed.

---

## 1. PV Access Modes

When requesting storage, developers must specify an **Access Mode** indicating how many nodes can read or write to the volume simultaneously.

| Access Mode | CLI Code | Description | Example Technologies |
|---|---|---|---|
| **ReadWriteOnce** | `RWO` | The volume can be mounted as read-write by a **single node**. Other nodes cannot attach to it. | AWS EBS, GCP Persistent Disk, Azure Disk, Local Disks |
| **ReadOnlyMany** | `ROX` | The volume can be mounted as read-only by **many nodes** simultaneously. | AWS EFS, Google Filestore, CephFS, Azure Files |
| **ReadWriteMany** | `RWX` | The volume can be mounted as read-write by **many nodes** simultaneously. | AWS EFS, Google Filestore, CephFS, NFS, GlusterFS |
| **ReadWriteOncePod** | `RWOP` | The volume can be mounted as read-write by a **single Pod** in the entire cluster. (Introduced in K8s v1.22+). | CSI-supported block storage requiring exclusive access. |

> [!WARNING]
> Access modes match **node count**, not **pod count**. Multiple pods running on the *same node* can mount a `ReadWriteOnce` volume simultaneously. However, if a pod on Node-A is writing to an RWO disk, a pod scheduled to Node-B cannot mount that disk.

---

## 2. PV Reclaim Policies

The reclaim policy tells Kubernetes what to do with the physical storage volume after the bound `PersistentVolumeClaim` is deleted:

* ### `Retain`
  * **Behavior**: The physical volume and its files are kept intact. The PV status changes to `Released`.
  * **Why it's used**: Safe database storage. If a developer accidentally deletes a PVC namespace, the database files are safe.
  * **Restoration**: An administrator must manually inspect the data, delete the PV resource, recreate the volume, or assign the data to a new PV.

* ### `Delete`
  * **Behavior**: Automatically deletes the `PersistentVolume` resource from Kubernetes and triggers the CSI driver to call the cloud provider's API to destroy the physical disk (e.g. deletes the AWS EBS volume).
  * **Why it's used**: Default policy for dynamic provisioning. Efficiently avoids orphan cloud costs.

* ### `Recycle` *(Deprecated)*
  * **Behavior**: Performs a basic file system wipe (`rm -rf /mount/*`) and makes the PV `Available` again for a new binding.
  * **Why it's deprecated**: Highly insecure and prone to data leak vulnerabilities.

---

## 3. CSI (Container Storage Interface) Internals

The CSI standardizes the storage plane by moving storage drivers out of the core Kubernetes binaries. It relies on standard Kubernetes Controllers and Kubelet APIs cooperating with external helper containers (Sidecars).

```
                             KUBERNETES CONTROL PLANE
                      ┌────────────────────────────────────┐
                      │          kube-apiserver            │
                      └──────────────────┬─────────────────┘
                                         │
                   ┌─────────────────────┼─────────────────────┐
                   │                     │                     │
                   ▼                     ▼                     ▼
         ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
         │external-provision│  │external-attacher │  │external-resizer  │
         │     sidecar      │  │     sidecar      │  │     sidecar      │
         └─────────┬────────┘  └─────────┬────────┘  └─────────┬────────┘
                   │ gRPC                │ gRPC                │ gRPC
                   ▼                     ▼                     ▼
         ┌──────────────────────────────────────────────────────────────┐
         │                     CSI Controller Plugin                    │
         │                (Communicates with Cloud Provider)            │
         └──────────────────────────────────────────────────────────────┘
```

### The CSI Sidecars Explained
* **`external-provisioner`**: Watches for new PVCs requiring dynamic allocation. It calls the CSI Driver's `CreateVolume` and `DeleteVolume` RPCs.
* **`external-attacher`**: Watches `VolumeAttachment` resources in K8s. It calls the driver's `ControllerPublishVolume` and `ControllerUnpublishVolume` to attach/detach the storage to the virtual or bare-metal host node.
* **`external-resizer`**: Watches PVC specification updates requesting larger capacity. It calls `ControllerExpandVolume` to extend the disk size on the cloud side.
* **`node-driver-registrar`**: Runs on worker nodes as a DaemonSet. It registers the CSI driver with the local Kubelet daemon so Kubelet knows which driver to call for OS mounts.

---

## 4. StatefulSet Identity & Ordinal Storage Mapping

`StatefulSets` are designed for stateful workloads like databases. They maintain a strict **ordinal index** (from `0` to `N-1`) for Pod naming, network DNS, and storage claims.

### Stable Storage Binding (The Magic Formula)
When you declare a `volumeClaimTemplates` block in a `StatefulSet` named `db`, Kubernetes automatically creates PVCs following the naming convention:
$$\text{PVC Name} = \text{volumeClaimTemplate.Name} - \text{StatefulSet.Name} - \text{Ordinal}$$

For example, a template named `data` for a StatefulSet named `db` creates:
* Pod `db-0` binds exclusively to PVC `data-db-0`
* Pod `db-1` binds exclusively to PVC `data-db-1`

```
  StatefulSet: db
  ┌───────────────┐          ┌───────────────┐
  │   Pod: db-0   │          │   Pod: db-1   │
  └───────┬───────┘          └───────┬───────┘
          │ (Mounts)                 │ (Mounts)
          ▼                          ▼
  ┌───────────────┐          ┌───────────────┐
  │ PVC: data-db-0│          │ PVC: data-db-1│
  └───────┬───────┘          └───────┬───────┘
          │ (Binds 1:1)              │ (Binds 1:1)
          ▼                          ▼
  ┌───────────────┐          ┌───────────────┐
  │  PV: pv-vol-0 │          │  PV: pv-vol-1 │
  └───────────────┘          └───────────────┘
```

### Re-scheduling Behavior
If Pod `db-1` crashes or its worker node dies:
1. The scheduler recreates Pod `db-1` on a healthy node.
2. The newly spawned Pod retains the exact name `db-1`.
3. Kubernetes matches the Pod with the existing PVC `data-db-1` and mounts the exact same Persistent Volume `pv-vol-1`.
4. The database replica boots up and reads its previous transaction log (WAL) from where it left off.

---

## 5. PersistentVolume States

A PV's lifecycle flows through a series of states:

```
[ PV Created ] ────► Available ────► Bound ────► Released
                        ▲                          │ (Reclaim Policy)
                        │                          ├─► Retain ──► (Manual Reset)
                        └──────────────────────────┴─► Delete ──► [*] (Destroyed)
```

1. **Available**: A free resource not yet bound to any PVC.
2. **Bound**: The volume has been allocated to a specific PVC claim.
3. **Released**: The PVC has been deleted, but the physical resource has not yet been processed by the cluster.
4. **Failed**: The automatic cleanup or reclaim loop failed. Admin intervention is required.
