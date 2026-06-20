# Container Storage Interface (CSI) & Volume Provisioning Lifecycle

This document explains the technical architecture of the CSI plugin model and details the end-to-end lifecycle of dynamically provisioned volumes.

---

## 🏛️ CSI Plugin Architecture
Prior to CSI (v1.13), volume provisioner drivers were compiled "in-tree" (directly inside the Kubernetes core binary). The Container Storage Interface decouples cloud storage vendors from core codebase operations by running out-of-tree plugins.

```
       Kubernetes Control Plane (API Server / Controller Manager)
                               │
                               ▼ (gRPC call over UNIX Socket)
                   ┌───────────────────────┐
                   │    CSI Controller     │ (Provision/Delete/Attach)
                   └───────────────────────┘
                               │
                               ▼ (API Calls)
                      Cloud Storage Provider (EBS/PD/Ceph)
                               │
                               ▼ (Physical Attach)
                      Worker Node Instance
                               │
                               ▼ (gRPC call over local socket)
                   ┌───────────────────────┐
                   │       CSI Node        │ (Mount/Format/Unmount)
                   └───────────────────────┘
```

A CSI Driver consists of three main components:
1.  **CSI Identity Service**: Reports the plugin's capabilities, health, and metadata back to the kubelet.
2.  **CSI Controller Service**: Runs on control plane nodes. Initiates cloud-side volume allocation, deletion, attachment, and detachment.
3.  **CSI Node Service**: Runs as a DaemonSet on every worker node. Handles the formatting and mounting of physical disks to pod namespace paths on host volumes.

---

## 🔄 Dynamic Volume Provisioning Lifecycle

The following sequence details how a volume is allocated and mounted when a user requests storage:

```
[1] PVC Created  ──> [2] StorageClass Match ──> [3] Provision Request ──> [4] Cloud Disk Allocated
                                                                                   │
[8] Container    <── [7] CSI Node Mount    <── [6] Pod Scheduled     <── [5] PV Created & Bound
    Running              (Format & Mount)          (Attach volume)
```

1.  **PVC Creation**: The user submits a `PersistentVolumeClaim` referencing a `StorageClass`.
2.  **StorageClass Match**: The volume controller matches the claim to the defined provisioner in the target StorageClass.
3.  **Provision Request**: The controller invokes the external CSI provisioner helper, calling the `CreateVolume` gRPC endpoint.
4.  **Cloud Storage Allocation**: The cloud provider API allocates the physical volume (e.g. AWS EBS volume).
5.  **PV Creation**: The controller creates a corresponding `PersistentVolume` object and binds it to the user's `PersistentVolumeClaim`.
6.  **Pod Scheduling**: The user's Pod is scheduled onto a worker node. The CSI controller calls `ControllerPublishVolume` to attach the disk to the target host virtual machine.
7.  **Mounting (CSI Node)**: The kubelet on the target worker node invokes the local CSI Node driver via `NodeStageVolume` (formats the raw disk with ext4/xfs) and `NodePublishVolume` (binds the path into the container's mount namespace).
8.  **Execution**: The container starts with the filesystem mounted directly to its local directory namespace.

---

## ⚙️ StorageClass Binding Modes
*   **Immediate**: Volumes are provisioned immediately when the PVC is created. This may cause scheduling failures if the volume is created in a availability zone (`us-east-1a`) where the scheduled pod's node does not reside.
*   **WaitForFirstConsumer** (Recommended): Postpones volume allocation until the Pod is scheduled. This guarantees the volume is provisioned in the exact availability zone where the target node resides.
