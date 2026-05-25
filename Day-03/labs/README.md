# 🛠️ Day 3 Hands-On Labs: Kubernetes Internals

Welcome to the hands-on lab exercises for Day 3. Here you will move from theory to practice, querying and manipulating the control plane components of a running Kubernetes cluster.

---

## 📋 Labs Overview

The labs are designed to run on a local development Kubernetes cluster (such as a multi-node **Kind** cluster or a single-node **Minikube** cluster). 

| Lab Module | Focus Area | Core Commands |
|---|---|---|
| 🧪 **[Lab 1: Inspect Control Plane](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-1-inspect-control-plane.md)** | Pod manifests, flags, and runtime status | `kubectl get pods -n kube-system` |
| 🧪 **[Lab 2: Trace API Requests](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-2-trace-api-requests.md)** | API Server request flow, raw curl, and verbosity | `kubectl get pods -v=8` / `curl` |
| 🧪 **[Lab 3: Scheduler Behavior](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-3-scheduler-behavior.md)** | Bypassing scheduler, node names, and affinity | `spec.nodeName` / Node Selectors |
| 🧪 **[Lab 4: Reconciliation Loops](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-4-reconciliation-loops.md)** | Observing scale delta, replica mismatch | `kubectl scale` / events tracing |
| 🧪 **[Lab 5: Inspect etcd Objects](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-5-inspect-etcd.md)** | Raw database key retrieval, protobuf payload | `etcdctl get` inside etcd container |
| 🧪 **[Lab 6: kubelet Operations](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-6-kubelet-operations.md)** | Host logs, static pod manifests, and systemd | `journalctl -u kubelet` / `/etc/kubernetes` |
| 🧪 **[Lab 7: kube-proxy Networking](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-7-kube-proxy-networking.md)** | Service iptables rules and IPVS tables | `iptables -t nat -L` / `ipvsadm` |
| 🧪 **[Lab 8: Node Failures & Pod Recovery](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-8-node-failures-pod-recovery.md)** | Eviction timers, status updates, cluster resilience | `docker stop` (Kind nodes) |

---

## ⚡ Prerequisites
Before starting:
1. Ensure you have **Docker** running.
2. Install **kubectl**.
3. Install **Kind** (Kubernetes in Docker) or **Minikube**. 
4. Standard Kind cluster configuration recommended for these labs (multiple nodes allow testing scheduling and node failures).

### Recommended: Spin Up a 3-Node Kind Cluster
Save the following configuration as `kind-config.yaml`:
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker2
```
And create the cluster:
```bash
kind create cluster --config kind-config.yaml --name k8s-internals
```
Verify connectivity:
```bash
kubectl cluster-info
kubectl get nodes -o wide
```
Once configured, proceed to **[Lab 1: Inspect Control Plane](file:///d:/30_Days_of_Production_Kubernetes/Day-03/labs/lab-1-inspect-control-plane.md)**!
