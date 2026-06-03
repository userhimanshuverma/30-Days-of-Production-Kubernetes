# 🛠️ Lab 4: Cluster Optimization with Quotas & LimitRanges

## Objective
Apply ResourceQuotas and LimitRanges to auto-inject defaults and restrict resource sprawl. Validate cluster-wide allocation statistics.

## Prerequisites
- A running Kubernetes cluster.

---

## Step 1: Deploy a LimitRange

A **LimitRange** enforces minimum, maximum, and default requests/limits for individual containers in a namespace.

Apply the `limit-range.yaml` manifest:
```bash
kubectl apply -f ../manifests/limit-range.yaml
```

Verify that the LimitRange is active:
```bash
kubectl describe limitrange default-limits
```
**Expected Output:**
```text
Name:       default-limits
Namespace:  default
Type        Resource  Min   Max  Default Request  Default Limit  Max Limit/Request Ratio
----        --------  ---   ---  ---------------  -------------  -----------------------
Container   cpu       50m   2    100m             500m           -
Container   memory    64Mi  4Gi  256Mi            512Mi          -
```

### Test LimitRange Auto-Injection
Now, apply the BestEffort Pod manifest `besteffort-pod.yaml` (which does not define a resources block):
```bash
kubectl apply -f ../manifests/besteffort-pod.yaml
```

Inspect the Pod's actual container spec:
```bash
kubectl get pod besteffort-pod -o jsonpath='{.spec.containers[0].resources}'
```
**Expected Output:**
```json
{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}
```
- The LimitRange **automatically injected** the default requests and limits.
- The Pod's QoS is now **Burstable** instead of BestEffort!

---

## Step 2: Deploy a ResourceQuota

A **ResourceQuota** restricts the total cumulative compute resource requests and limits in a namespace.

Apply the `resource-quota.yaml` manifest:
```bash
kubectl apply -f ../manifests/resource-quota.yaml
```

### Inspect the Quota State
```bash
kubectl describe quota team-alpha-quota
```
**Expected Output:**
```text
Name:            team-alpha-quota
Namespace:       default
Resource         Used   Hard
--------         ----   ----
limits.cpu       500m   8
limits.memory    512Mi  16Gi
pods             1      10
requests.cpu     100m   4
requests.memory  256Mi  8Gi
```
Here you can see the *Hard limits* you set, and the *Used resources* which currently count the `besteffort-pod` we deployed.

---

## Step 3: Test Quota Violations

Let's try to deploy the `production-workloads.yaml` file, which contains workloads requesting large amounts of resources.

```bash
kubectl apply -f ../manifests/production-workloads.yaml
```

You will see error messages indicating that the creation was rejected by the Admission controller:
```text
Error from server (Forbidden): error submitting customer-db StatefulSet: pods "customer-db-0" is forbidden: exceeded quota: team-alpha-quota, requested: requests.cpu=4,requests.memory=16Gi, used: requests.cpu=100m,requests.memory=256Mi, limited: requests.cpu=4,requests.memory=8Gi
```
- The Admission Controller checked the Pod creation request against the `ResourceQuota`.
- Because the requested memory (`16Gi`) exceeds the quota limit of `8Gi`, the API server **refused** to create the StatefulSet.

---

## Step 4: Cluster-wide Allocation Analysis

To optimize a cluster's utilization, a platform engineer needs to check how close the total reservations are to actual capacity.

You can inspect the resource allocations of all nodes using this command:
```bash
kubectl describe nodes | grep -A 10 "Allocated resources"
```
**Expected Output:**
```text
Allocated resources:
  (Total limits may be over 100%, but total requests should not exceed node capacity)
  Resource           Requests    Limits
  --------           --------    ------
  cpu                600m (15%)  1000m (25%)
  memory             512Mi (6%)  1024Mi (12%)
```
This summary gives you the total percentage of resources scheduled on the cluster. If requests are very low (e.g. <20%), your cluster is over-provisioned, representing a cost-optimization opportunity (e.g., downsizing nodes or using bin-packing).

---

## Clean Up
```bash
kubectl delete -f ../manifests/limit-range.yaml
kubectl delete -f ../manifests/resource-quota.yaml
kubectl delete pod besteffort-pod
```
