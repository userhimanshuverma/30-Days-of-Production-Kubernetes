# 🚨 Troubleshooting Playbook: Backup, HA & Disaster Recovery

This playbook provides actionable diagnostic steps and resolution guides for common outages related to etcd, multi-zone clusters, and high-availability operations.

---

## 💥 Issue 1: `mvcc: database space exceeded` (etcd write block)

### Symptoms
* Developers cannot deploy new resources; errors return `etcdserver: mvcc: database space exceeded`.
* Control plane nodes remain `Ready`, but `kubectl` writes (e.g. `kubectl apply`, `kubectl delete`) fail.
* Prometheus alerts fire for `etcdDbSizeLimitExceeded`.

### Root Cause
etcd has reached its hard storage quota limit (default is 2GB in many environments). Reads are allowed, but all write transactions are blocked by etcd to prevent database corruption.

### Investigation
1. SSH into a control plane node and check the database file size:
   ```bash
   sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     -w table endpoint status
   ```
   *Verify if `DB SIZE` is near the quota limit (e.g. 2.1 GB).*

2. Get the current revision:
   ```bash
   sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     endpoint status -w json | grep -o '"revision":[0-9]*'
   ```

### Resolution
To unlock the database, you must **compact history**, **defragment the DB**, and **clear the alarm**:

1. **Compact the database** to the latest revision (e.g., `5180290`):
   ```bash
   sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     compact 5180290
   ```

2. **Defragment etcd** to shrink the physical file size and release space (run this on each node):
   ```bash
   sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     defrag
   ```

3. **Disarm the database alarm**:
   ```bash
   sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     alarm disarm
   ```

### Prevention
* Increase the quota limit in `/etc/kubernetes/manifests/etcd.yaml` by passing the `--quota-backend-bytes=8589934592` (8GB) flag.
* Ensure auto-compaction is enabled by verifying the presence of `--auto-compaction-retention=5m` or `--auto-compaction-retention=1` (hour).

---

## 🛑 Issue 2: etcd Split-Brain (Consensus Desynchronization)

### Symptoms
* Different `kubectl get` commands return different/stale results depending on which API server handles the request.
* `kube-apiserver` logs show errors: `etcdserver: duplicate key`, `etcdserver: request timed out`.
* etcd logs show: `raft: member ... has divergent history`.

### Root Cause
A network partition isolated one or more etcd members, causing them to diverged from the leader. If the partition lasts too long, they cannot reconcile when reunited.

### Investigation
1. Compare revisions on all etcd endpoints:
   ```bash
   # Query status on all control plane IPs
   for ip in 10.0.0.11 10.0.0.12 10.0.0.13; do
     sudo ETCDCTL_API=3 etcdctl --endpoints=https://${ip}:2379 \
       --cacert=/etc/kubernetes/pki/etcd/ca.crt \
       --cert=/etc/kubernetes/pki/etcd/server.crt \
       --key=/etc/kubernetes/pki/etcd/server.key \
       endpoint status
   done
   ```
   *Look for mismatched `REVISION` numbers or divergent hashes.*

### Resolution
1. Identify the node with the stale/diverged state (e.g. `master-03`).
2. SSH into `master-03` and stop its etcd member:
   ```bash
   sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/
   ```
3. Remove the diverged member from the healthy etcd cluster (on `master-01`):
   ```bash
   sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 ... member remove <stale-member-id>
   ```
4. Wipe the etcd data directory on `master-03`:
   ```bash
   sudo rm -rf /var/lib/etcd/*
   ```
5. Add the member back (on `master-01`):
   ```bash
   sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 ... member add master-03 --peer-urls=https://10.0.0.13:2380
   ```
6. Restore `etcd.yaml` to `/etc/kubernetes/manifests/` on `master-03` to start etcd, allowing it to sync clean state from the leader.

### Prevention
* Implement network policies that guarantee dedicated, high-bandwidth, low-latency links between control plane nodes.
* Set alert thresholds on `etcd_network_peer_round_trip_time_seconds`.

---

## ⚡ Issue 3: Backup Job Fails to Run (Permission Denied)

### Symptoms
* Automated backup CronJob shows `Failed` or stays in `Error` status.
* Pod logs show: `open /backup/etcd-snapshot-xxxx.db: permission denied` or `cannot read certificates`.

### Root Cause
The backup container runs as a non-privileged user or lack permission to access host-mounted folders (`/var/backups`) or etcd secrets (`/etc/kubernetes/pki/etcd`).

### Investigation
Inspect the CronJob logs and Pod events:
```bash
kubectl logs -n kube-system -l k8s-app=etcd-backup
kubectl describe pod -n kube-system -l k8s-app=etcd-backup
```
Check if the HostPath volume has restrictive permissions on the host system:
```bash
ls -ld /etc/kubernetes/pki/etcd
ls -ld /var/backups/kubernetes/etcd
```

### Resolution
1. Ensure the CronJob Pod spec has `hostNetwork: true`.
2. Ensure the container has security contexts if using PSPs or Kyverno policies:
   ```yaml
   securityContext:
     privileged: true
   ```
3. Ensure directory permissions on the host hostPath mounts allow writes (e.g. `chmod 700 /var/backups/kubernetes/etcd`).

---

## 💾 Issue 4: Stuck PersistentVolume Attachment after Zone Failure

### Symptoms
* An Availability Zone fails (e.g. `us-east-1a`).
* A StatefulSet pod (like `postgres-0`) is rescheduled to a node in `us-east-1b`.
* The pod remains stuck in `ContainerCreating` or `VolumeAttachment` phase.
* Events show: `Multi-Attach error for volume ... volume is already exclusively attached to one node`.

### Root Cause
The cloud provider's controller thinks the volume is still attached to the dead node in the failed zone. The block storage API refuses to attach the volume to a node in a different zone because cloud volumes are zone-locked.

### Investigation
Check the status of `VolumeAttachment` resources in the cluster:
```bash
kubectl get volumeattachments
```
Inspect the description of the stuck pod:
```bash
kubectl describe pod postgres-0
```

### Resolution
1. **Force eviction**: Cordon and drain the dead node immediately to signal that it is lost.
2. **Delete VolumeAttachment**: If the cloud controller fails to detach the volume from the dead node, manually delete the `VolumeAttachment` resource:
   ```bash
   kubectl delete volumeattachment <attachment-id> --grace-period=0 --force
   ```
3. **Verify Zone Mapping**: If the application requires access to the same data, restore the volume from a regional snapshot into the surviving zone, update the PersistentVolume (`PV`) spec, and restart the pod.
