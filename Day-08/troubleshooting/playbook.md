# 🚨 Day 08 Troubleshooting Playbook — Kubernetes Storage & Volumes

This playbook details 10 real-world production storage bugs, guiding you through symptoms, root cause analysis, diagnostic commands, and recovery actions.

---

## 1. PVC Stuck in `Pending` Forever

### Symptoms
You run `kubectl get pvc` and see the status stuck in `Pending`. The corresponding Pod remains in `Pending` or `ContainerCreating`.

### Root Cause
1. No matching `PersistentVolume` (PV) satisfies the capacity or AccessMode requested in the claim.
2. The requested `StorageClass` does not exist.
3. The StorageClass is configured with `volumeBindingMode: WaitForFirstConsumer`, and the Pod using it cannot schedule due to scheduling conflicts (e.g., node selectors, taints).

### Investigation
```bash
# Get details and events of the PVC
kubectl describe pvc <pvc-name>

# View cluster StorageClasses
kubectl get sc
```

Look at the `Events` section. Common messages:
* `"storageclass.storage.k8s.io <sc-name> not found"`
* `"waiting for first consumer to be created before binding"`

### Resolution
* **If StorageClass is missing**: Fix the typo in the PVC `storageClassName` or create the StorageClass.
* **If waiting for consumer**: Inspect the Pod using the PVC:
  ```bash
  kubectl describe pod <pod-name>
  ```
  Fix node constraints or resources so the Pod can be scheduled.

### Prevention
Implement linting checks on Helm charts and Kubernetes manifests to ensure storage class names match the target environment.

---

## 2. MountVolume.SetUp Failed

### Symptoms
The Pod is stuck in `ContainerCreating` or `CrashLoopBackOff`. Running `kubectl describe pod` reveals:
```
Warning  FailedMount  12s  kubelet  MountVolume.SetUp failed for volume "pv-name" : mount failed: exit status 32
```

### Root Cause
The node's host OS cannot mount the disk. This occurs if:
1. The filesystem on the disk (e.g., ext4, xfs) is corrupted.
2. The CSI driver lacks the utility binaries on the host node (`mkfs.ext4` or `xfsprogs`).
3. SELinux or AppArmor blocks host mounts.

### Investigation
```bash
# Check the event details on the failing Pod
kubectl describe pod <pod-name>

# Check Kubelet system logs on the worker node
journalctl -u kubelet -n 100 --no-pager
```

### Resolution
If the volume is new and the node lacks tools, install standard filesystem utilities on the worker nodes:
```bash
# Ubuntu/Debian
apt-get install -y xfsprogs e2fsprogs
```
If the disk is corrupted, spin up a recovery Pod on the target node, mount the disk, and run `fsck`.

### Prevention
Ensure worker node base images (AMIs/VM templates) pre-install core storage binaries.

---

## 3. CSI Driver Node Registration Failures

### Symptoms
Dynamic provisioning fails. Pods scheduled to a node cannot attach storage, and logs report:
```
CSI driver name ebs.csi.aws.com not found in the list of registered drivers
```

### Root Cause
The `node-driver-registrar` DaemonSet container failed to register the local CSI driver daemon with the node's Kubelet. This is usually due to mismatched socket file paths.

### Investigation
```bash
# Check CSI DaemonSet pod status
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Inspect logs of the node-driver-registrar container
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver -c node-driver-registrar
```

### Resolution
Verify Kubelet is running with the default directory path (`/var/lib/kubelet`). If your cluster uses a custom path, update the CSI DaemonSet manifest volume mount configuration to match that custom socket directory.

### Prevention
Use verified Helm charts provided by cloud vendors and carefully override the default directories when building custom OS clusters.

---

## 4. StorageClass Mismatch on Claims

### Symptoms
PVCs fail to bind, showing messages like:
```
provisioning failed: no volume plugin matches name...
```

### Root Cause
The developer applied a manifest specifying a StorageClass that is incompatible with the host environment (e.g., deploying an AWS `gp3` StorageClass to a local Minikube or Bare-Metal cluster).

### Investigation
```bash
kubectl get sc
kubectl describe pvc <pvc-name>
```

### Resolution
Update the PVC `storageClassName` to match the default class of your current environment (e.g., `standard` on Minikube, `local-path` on Kind). Alternatively, set the local StorageClass as the default:
```bash
kubectl patch storageclass <local-sc-name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Prevention
Use template parameters or variables in your CI/CD pipelines to dynamically set storage classes depending on target environment variables.

---

## 5. Slow Disk Performance & Throttling

### Symptoms
Database queries latency spikes, transaction logs write times grow, and database logs report disk queue alerts.

### Root Cause
The storage volume has hit the IOPS or throughput limit of the cloud provider tier.

### Investigation
1. Check cloud provider console metrics (e.g., AWS CloudWatch for EBS volume IOPS burst credits).
2. Measure node performance using tool execution inside a scratch container:
   ```bash
   kubectl run fio-test --rm -i --tty --image=alpine/fio -- -readwrite=randwrite -directory=/data -size=1G
   ```

### Resolution
* If using `gp3`, modify the StorageClass parameters to provision higher IOPS and throughput, then apply the expanded spec.
* Move database workloads to local NVMe SSDs (`local-storage` class).

### Prevention
Set up Prometheus alerts monitoring `volume_manager_status` metrics and disk utilization levels.

---

## 6. Failed Dynamic Provisioning (Cloud IAM Permissions)

### Symptoms
PVC remains `Pending` and logs show:
```
Failed to provision volume with StorageClass "gp3": unauthorized / AccessDenied
```

### Root Cause
The CSI controller service account lacks the required IAM permissions to call the Cloud Provider storage API (e.g., `ec2:CreateVolume` on AWS).

### Investigation
```bash
# Check Controller logs
kubectl logs -n kube-system -l app=ebs-csi-controller -c csi-provisioner
```
Look for `AccessDenied` or credential validation error messages.

### Resolution
Associate the CSI controller ServiceAccount with an IAM Role containing appropriate permissions (IRSA - IAM Roles for Service Accounts):
```bash
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster <cluster-name> \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

### Prevention
Always provision cloud infra roles via Terraform to ensure cluster workloads have deterministic IAM attachments.

---

## 7. Multi-Attach Errors (RWO Volumes)

### Symptoms
A Pod is stuck in `ContainerCreating` forever, and events show:
```
Warning  FailedAttachVolume  3s  attachdetach-controller  Multi-Attach error for volume "pv-name" Volume is already used by Pod
```

### Root Cause
A `ReadWriteOnce` volume is attached to Node-A where Pod v1 is running. During a rolling update, Pod v2 is scheduled to Node-B. Since the volume is `ReadWriteOnce`, the cloud provider cannot attach it to Node-B until Node-A completely releases it.

### Investigation
```bash
# Find which Pod is currently locking the volume
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.volumes[*].persistentVolumeClaim.claimName}{"\n"}{end}' | grep <pvc-name>
```

### Resolution
1. Change your deployment strategy from `RollingUpdate` to `Recreate` for single-replica stateful workloads:
   ```yaml
   spec:
     strategy:
       type: Recreate
   ```
2. If a node crashes cleanly and the volume hangs, force delete the stuck Pod or wait for Node Lease timeout eviction.

### Prevention
Avoid running databases as standard `Deployments` with RollingUpdate. Use `StatefulSets` instead.

---

## 8. Volume Expansion Stuck

### Symptoms
You modified a PVC spec to request a larger size, but the PVC status reports:
```
Conditions:
  Type                      Status  LastTransitionTime    Reason  Message
  ----                      ------  ------------------    ------  -------
  VolumeExpansionInProgress True    2026-05-30T18:00:00Z  ...     Waiting for user pod to recover...
```

### Root Cause
The CSI Controller successfully resized the disk in the cloud, but the OS filesystem resizing has not occurred because the target Pod is not running or cannot mount the volume.

### Investigation
```bash
kubectl describe pvc <pvc-name>
```

### Resolution
Ensure the Pod using the PVC is running. If it is stuck in a loop, force a restart:
```bash
kubectl delete pod <pod-name>
```
Once the Pod starts on a node, Kubelet executes filesystem resizing, and the PVC status updates to show the new size.

### Prevention
Verify that `allowVolumeExpansion` is enabled on the `StorageClass` *before* attempting modifications.

---

## 9. Node Storage Failure or Disk Corruption

### Symptoms
The database container throws I/O errors (`Read-only file system` or `I/O error`). Kubelet marks the node status as `DiskPressure` or `Unhealthy`.

### Root Cause
The host node's underlying storage controller failed, or the local physical disk has bad sectors.

### Investigation
```bash
kubectl get nodes
# SSH to Node and run dmesg
dmesg | grep -iE 'io|error|ext4|journal'
```

### Resolution
1. Drain the worker node:
   ```bash
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```
2. The Pod is rescheduled on a healthy node, forcing the RWO volume to detach from the failed node and mount to the healthy one.
3. Replace the failed node hardware.

### Prevention
Configure monitoring alerts for node `DiskPressure` states and system errors.

---

## 10. Accidental PV Deletion with `Retain` Policy

### Symptoms
A developer deletes a namespace or PVC containing critical data. The PVC is gone, but the PV status is `Released`. You want to map this data to a new Pod.

### Root Cause
The PV has a `Retain` reclaim policy. The actual data is intact, but because the PV `claimRef` still points to the deleted PVC, it cannot be claimed by other PVCs.

### Investigation
```bash
kubectl get pv
# Note the status: Released
```

### Resolution
1. Export the PV definition:
   ```bash
   kubectl get pv <pv-name> -o yaml > pv-recovery.yaml
   ```
2. Edit `pv-recovery.yaml` and remove the `claimRef` block from `spec`:
   ```yaml
   # Remove this block entirely
   claimRef:
     apiVersion: v1
     kind: PersistentVolumeClaim
     name: pg-data
     namespace: default
     uid: ...
   ```
3. Re-apply the manifest. The PV status will return to `Available`.
4. Create a new PVC referencing the PV name.

### Prevention
Restrict RBAC permissions for deleting namespaces and claims in production environments.
