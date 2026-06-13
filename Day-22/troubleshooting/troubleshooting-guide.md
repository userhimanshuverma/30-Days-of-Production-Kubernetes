# 🚨 Troubleshooting Scheduling Failures: SRE Playbook

This playbook outlines step-by-step diagnostics and resolutions for common Kubernetes scheduling incidents in production.

---

## 🔍 Diagnostic Toolkit

Before diving into specific issues, run these commands to inspect the cluster scheduler state:

```bash
# 1. View the events block of a pending Pod (the primary way to diagnose scheduler rejections)
kubectl describe pod <pod-name> -n <namespace>

# 2. View scheduler control plane logs
kubectl logs -n kube-system -l component=kube-scheduler

# 3. Check node allocatable resources and taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU_ALLOCATABLE:.status.allocatable.cpu,MEM_ALLOCATABLE:.status.allocatable.memory,TAINTS:.spec.taints

# 4. View events sorted by type/time across the namespace
kubectl get events -n default --sort-by='.metadata.creationTimestamp'
```

---

## 📋 Incident Playbooks

### Incident 1: Pod is stuck in `Pending` with `0/3 nodes are available: 3 Insufficient cpu`

#### 🔴 Symptoms
* Pod remains in `Pending` state indefinitely.
* Events show `FailedScheduling` warnings.

#### 🔎 Root Cause
No worker node in the cluster has enough unreserved (allocatable) CPU capacity to meet the Pod's CPU request (`requests.cpu`). Note that scheduling is based on *reservations* (requests), not actual usage.

#### 🔧 Resolution
1. **Analyze requests**: Check if the Pod's CPU request is unnecessarily large. Downsize if possible.
2. **Examine nodes**: Check node CPU allocations:
   ```bash
   kubectl describe nodes | grep -A 10 "Allocated resources"
   ```
3. **Trigger scale-up**: If requests are valid, add more nodes or configure Cluster Autoscaling / Karpenter.

---

### Incident 2: Pod stuck with `node(s) had untolerated taint`

#### 🔴 Symptoms
* Pod remains `Pending`.
* Event description contains: `0/3 nodes are available: 1 node(s) had untolerated taint, 2 node(s) were unschedulable.`

#### 🔎 Root Cause
The Pod is either targeting nodes that have taints applied without possessing the corresponding tolerations, or it has a typo in its `tolerations` configuration.

#### 🔧 Resolution
1. Inspect the taints on the target node:
   ```bash
   kubectl get node <node-name> -o jsonpath='{.spec.taints}'
   ```
2. Verify that the Pod's `tolerations` block matches the node's taint configuration exactly:
   ```yaml
   # Check keys, values, and effects (e.g. NoSchedule vs NoExecute)
   tolerations:
   - key: "specialized-workload"
     operator: "Equal"
     value: "true"
     effect: "NoSchedule"
   ```

---

### Incident 3: Affinity Loop Conflict (Pod stays `Pending` indefinitely)

#### 🔴 Symptoms
* Multiple Pod deployments are stuck in `Pending` state.
* Logs show circular dependency rejections during the Pod Affinity filtering phase.

#### 🔎 Root Cause
You have defined conflicting hard affinity rules (e.g., Pod A must run on the same node as Pod B, and Pod B must run on a node with Pod C, but Pod C has an anti-affinity rule with Pod A).

#### 🔧 Resolution
1. Map out the affinity rules of all related Pods.
2. Replace hard requirements (`requiredDuringSchedulingIgnoredDuringExecution`) with soft preferences (`preferredDuringSchedulingIgnoredDuringExecution`) for non-critical dependencies:
   ```diff
   - requiredDuringSchedulingIgnoredDuringExecution:
   + preferredDuringSchedulingIgnoredDuringExecution:
   + - weight: 50
   +   podAffinityTerm:
   +     ...
   ```

---

### Incident 4: Zone Imbalance & Topology Constraint Failures

#### 🔴 Symptoms
* Replicas are not scaling up, showing `FailedScheduling` events pointing to `node(s) didn't match PodTopologySpread`.
* Worker nodes are under-utilized in one zone, and over-utilized in another.

#### 🔎 Root Cause
The `topologySpreadConstraints` block contains a hard skew limit (`whenUnsatisfiable: DoNotSchedule`) that cannot be met due to a zone outage, unequal node allocation per zone, or insufficient node counts in one zone.

#### 🔧 Resolution
1. Check node counts in each availability zone:
   ```bash
   kubectl get nodes -L topology.kubernetes.io/zone
   ```
2. Temporarily relax constraints to allow scheduling during zone degradation:
   ```yaml
   whenUnsatisfiable: ScheduleAnyway
   ```
