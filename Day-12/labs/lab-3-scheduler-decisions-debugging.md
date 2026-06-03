# 🛠️ Lab 3: Scheduler Decisions & Debugging Pending Pods

## Objective
Intentionally trigger a scheduling failure, inspect scheduler decisions, and resolve placement failures.

## Prerequisites
- A running Kubernetes cluster.

---

## Step 1: Deploy a Pod that exceeds Node Capacity

First, let's check the size of the nodes in our cluster to find the maximum allocatable CPU:
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory
```
*Example Output:*
```text
NAME                 CPU   MEM
kind-control-plane   4     7900428Ki
```
Here, our single control-plane node has 4 CPUs allocatable.

Now, let's write a manifest for a Pod that requests more resources than are available. For example, if your node has 4 CPUs, write a manifest that requests 6 CPUs.

Create a temporary manifest `over-requested-pod.yaml`:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: massive-pod
spec:
  containers:
  - name: server
    image: alpine:latest
    command: ["sleep", "3600"]
    resources:
      requests:
        cpu: "6" # Exceeds node allocatable capacity
        memory: "2Gi"
```
Apply this manifest:
```bash
kubectl apply -f over-requested-pod.yaml
```

---

## Step 2: Diagnose the Pending Pod

Check the state of the Pod:
```bash
kubectl get pod massive-pod
```
**Expected Output:**
```text
NAME          READY   STATUS    RESTARTS   AGE
massive-pod   0/1     Pending   0          10s
```

### Inspect the Scheduler Events
Run the `describe` command to see the decision-making logs from the scheduler:
```bash
kubectl describe pod massive-pod
```

Look at the **Events** section at the bottom of the output. You should see a `FailedScheduling` warning event:
```text
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  12s   default-scheduler  0/1 nodes are available: 1 Insufficient cpu. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod..
```
### Analyze the Error Message
- **`0/1 nodes are available`**: The scheduler evaluated 1 candidate node in the cluster.
- **`1 Insufficient cpu`**: The node failed the **NodeResourcesFit** predicate check because the requested CPU (`6`) exceeds the node's allocatable CPU (which is `4`).
- **`No preemption victims found`**: The scheduler tried to see if it could evict existing lower-priority Pods to free up space, but found no suitable candidates.

---

## Step 3: Resolve the Scheduling Failure

To fix the scheduling failure, we have three options:
1. **Reduce the Pod's request** to fit inside the node.
2. **Add more nodes** to the cluster (horizontal scaling).
3. **Upgrade the instance size** of the node (vertical scaling).

Let's modify the CPU request of `massive-pod` to a values that fits inside the node (e.g., `500m`).

Apply a corrected spec:
```bash
kubectl patch pod massive-pod --type='json' -p='[{"op": "replace", "path": "/spec/containers/0/resources/requests/cpu", "value": "500m"}]'
```
*Note: Since Pod specifications are largely immutable after creation, Kubernetes will return an error if you patch directly. Let's delete and re-apply instead.*

```bash
kubectl delete pod massive-pod
```

Create a new file `massive-pod-fixed.yaml` with requests set to `500m` CPU:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: massive-pod
spec:
  containers:
  - name: server
    image: alpine:latest
    command: ["sleep", "3600"]
    resources:
      requests:
        cpu: "500m"
        memory: "2Gi"
```
Apply it:
```bash
kubectl apply -f massive-pod-fixed.yaml
```

Check the status:
```bash
kubectl get pod massive-pod
```
**Expected Output:**
```text
NAME          READY   STATUS    RESTARTS   AGE
massive-pod   1/1     Running   0          5s
```

Verify that scheduling was completed successfully by looking at the event logs again:
```bash
kubectl describe pod massive-pod
```
You should see:
```text
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  10s   default-scheduler  Successfully assigned default/massive-pod to kind-control-plane
```

---

## Clean Up
```bash
kubectl delete pod massive-pod
```
