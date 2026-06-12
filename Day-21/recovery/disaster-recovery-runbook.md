# 🚨 Disaster Recovery Runbook (Production Incident Response)

This document provides step-by-step instructions for recovering a production Kubernetes cluster from catastrophic control plane failures, database corruption, or availability zone outages.

---

## 🛑 Scenario A: Lost 1 of 3 etcd Members (Degraded Quorum)

In a 3-node control plane configuration, if **one** control plane node is lost, the etcd cluster is degraded but still has quorum (2/3 nodes active). **Do not run a snapshot restore in this case!** Instead, remove the failed member and add a new one.

### 1. Identify the status of members
On a healthy control plane node, query the member list:
```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```
**Output Example**:
```text
8e64e521e8e3d3a0, started, master-01, https://10.0.0.11:2380, https://10.0.0.11:2379, false
a431c19b02a9eb71, started, master-02, https://10.0.0.12:2380, https://10.0.0.12:2379, false
f712d91bc5a5e3e2, unstarted, master-03, https://10.0.0.13:2380, https://10.0.0.13:2379, false
```
*Note that `master-03` is unstarted or unresponsive.*

### 2. Remove the failed member
Remove the ID of the failed node (in this case, `f712d91bc5a5e3e2`):
```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member remove f712d91bc5a5e3e2
```

### 3. Join a new member node
Provision a fresh control plane node (`master-03-new` with IP `10.0.0.14`), then register it:
```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member add master-03-new --peer-urls=https://10.0.0.14:2380
```
Follow the output instructions to start etcd on the new node with the updated `--initial-cluster` flags.

---

## 💥 Scenario B: Full etcd Database Corruption (Loss of Quorum)

If **two or more** nodes fail, or the database is corrupted, the cluster is down. You must restore from the latest verified snapshot.

### Step 1: Declare Incident & Notify Stakeholders
* Notify SRE, Platform, and App Dev teams.
* Log into the central monitoring system and silence alerting routes for this cluster to prevent pager fatigue.

### Step 2: Retrieve the Latest Verified Backup
Locate the last healthy backup file on remote storage (e.g., S3):
```bash
aws s3 cp s3://company-k8s-dr-backups/etcd-snapshots/master-01/etcd-snapshot-latest.db /tmp/etcd-snapshot-latest.db
```

### Step 3: Run the Restore Script on Node 1
Copy the backup file to your first master node (`master-01`) and run the recovery script:
```bash
sudo ./etcd-restore.sh /tmp/etcd-snapshot-latest.db
```

### Step 4: Re-initialize the Other Control Plane Nodes
Once `master-01` is back online and its API server is running, you must synchronize the state to `master-02` and `master-03`:
1. SSH into `master-02` and `master-03`.
2. Stop their control plane static pods (move files out of `/etc/kubernetes/manifests`).
3. Delete the corrupted data directories: `sudo rm -rf /var/lib/etcd`.
4. Copy the newly restored `/var/lib/etcd` directory from `master-01` to `master-02` and `master-03` via `rsync` or re-join them using `kubeadm join --control-plane`.
5. Re-enable the static pods.

---

## ⚡ Scenario C: Complete Availability Zone Outage (AZ Failure)

If a physical data center or cloud availability zone (e.g., `us-east-1a`) goes dark, workloads must failover to surviving zones.

### 1. Verify Node and Pod Statuses
Identify nodes in the failed zone and their current taint status:
```bash
kubectl get nodes -l topology.kubernetes.io/zone=us-east-1a
```
Nodes will transition to `NotReady`. By default, Kubernetes waits 5 minutes (`pod-eviction-timeout`) before evicting pods from `NotReady` nodes.

### 2. Fast-Track Evictions (Emergency Triage)
If an AZ outage is confirmed, do not wait for the timeout. Manually cordon and drain the affected nodes to force the scheduler to spin up replicas in surviving zones:
```bash
# Get all nodes in the failed zone and drain them
for node in $(kubectl get nodes -l topology.kubernetes.io/zone=us-east-1a -o name); do
  kubectl cordon $node
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data --force --grace-period=0
done
```

### 3. Verify Stateful Workloads (PVC Attachments)
Stateful sets with PVCs bound to the failed zone **cannot** easily failover because cloud disks (e.g. AWS EBS) are zone-locked.
* **Mitigation**: Promote the database replica running in the secondary zone (e.g., `us-east-1b`) to Leader.
* **Resolution**: Restore database backup to a new volume provisioned in the healthy zone.

---

## 🧪 Post-Recovery Verification Checklist
Once the restore completes, verify cluster operations:

- [ ] Check cluster component health:
  ```bash
  kubectl get componentstatuses
  ```
- [ ] Check node readiness:
  ```bash
  kubectl get nodes
  ```
- [ ] Verify that CoreDNS and CNI (Calico/Cilium) pods are running:
  ```bash
  kubectl get pods -n kube-system
  ```
- [ ] Validate application connectivity by hitting a test endpoint:
  ```bash
  curl -I https://payment-gateway.production.svc.cluster.local/healthz
  ```
- [ ] Run a test deployment to ensure the write path to etcd is working:
  ```bash
  kubectl create deployment dr-write-test --image=nginx
  kubectl delete deployment dr-write-test
  ```
