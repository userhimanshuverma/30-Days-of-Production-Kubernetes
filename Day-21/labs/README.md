# 🛠️ Day 21 Hands-On Labs: Disaster Recovery & High Availability

Welcome to the hands-on operations lab for Day 21. Here, you will act as a Site Reliability Engineer (SRE) managing backup execution, restore flows, multi-zone workloads, and simulating active failover scenarios.

---

## 🎯 Lab Objectives
By completing these labs, you will:
1. **Lab 1**: Perform a manual etcd snapshot and restore on a local control plane, verifying that cluster resources recover cleanly.
2. **Lab 2**: Deploy a multi-zone application utilizing **Topology Spread Constraints** and **Pod Disruption Budgets**, and inspect how scheduler decisions shift.
3. **Lab 3**: Simulate control plane degradation and zone network cuts, watching how the Raft quorum responds and heals.

---

## 📋 Prerequisites & Tools
* **Kubernetes Cluster**: A local cluster where you have root access to the master nodes is highly recommended. 
  - *For Lab 1 and Lab 3*: We recommend using a single-node or multi-node **Kind (Kubernetes-in-Docker)** cluster, as it runs control-plane components as Docker containers, allowing easy access to the virtual host filesystem and etcd data.
  - *For Lab 2*: Any standard cluster (Kind, Minikube, or cloud) will work, but a multi-node cluster is ideal.
* **Tools**:
  - `kubectl` configured to point to your lab cluster.
  - `etcdctl` CLI binary installed on your local host (to interact with etcd).
  - Docker CLI installed.

---

## 📂 Lab Directory Structure

Each lab is documented in its own markdown file:

1. **[Lab 1: etcd Backup and Restore](file:///d:/30_Days_of_Production_Kubernetes/Day-21/labs/lab-1-etcd-backup-restore.md)**: Manual etcd snap-and-restore walkthrough.
2. **[Lab 2: Multi-Zone Topology Spread](file:///d:/30_Days_of_Production_Kubernetes/Day-21/labs/lab-2-multizone-topology-spread.md)**: YAML scheduling constraints and PDB validation.
3. **[Lab 3: Simulating Control Plane Failures](file:///d:/30_Days_of_Production_Kubernetes/Day-21/labs/lab-3-simulating-control-plane-failures.md)**: Node crashes, network partitioning, and Raft consensus testing.

---

## 🚀 Setting Up the Lab Cluster (via Kind)

To simulate a multi-node cluster locally, write the following Kind config to a file named `kind-ha-cluster.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  # 3 Control Plane Nodes (HA setup)
  - role: control-plane
  - role: control-plane
  - role: control-plane
  # 3 Worker Nodes
  - role: worker
  - role: worker
  - role: worker
```

Create the cluster:
```bash
kind create cluster --config kind-ha-cluster.yaml --name k8s-production-ops
```

Verify your cluster topology:
```bash
kubectl get nodes -o wide
```
This creates a local replica of a high-availability production cluster with 3 control plane nodes running stacked etcd!
