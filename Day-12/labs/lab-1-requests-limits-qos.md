# 🛠️ Lab 1: Requests, Limits, and QoS Classification

## Objective
Configure varying resource limits for CPU and Memory, and observe how Kubernetes automatically assigns QoS classes.

## Prerequisites
- A running Kubernetes cluster (e.g., Kind or Minikube).
- `kubectl` configured to point to your cluster.

---

## Step 1: Deploy a Guaranteed QoS Pod
Apply the `guaranteed-pod.yaml` manifest.

```bash
kubectl apply -f ../manifests/guaranteed-pod.yaml
```

Verify that the Pod was scheduled and is running:
```bash
kubectl get pod guaranteed-pod
```

### Inspect the QoS Class
Run the following command to retrieve the QoS class determined by Kubernetes:
```bash
kubectl get pod guaranteed-pod -o jsonpath='{.status.qosClass}'
```
**Expected Output:**
```text
Guaranteed
```

Inspect details using `describe`:
```bash
kubectl describe pod guaranteed-pod
```
Look at the bottom of the output for `QoS Class: Guaranteed`.

---

## Step 2: Deploy a Burstable QoS Pod
Apply the `burstable-pod.yaml` manifest.

```bash
kubectl apply -f ../manifests/burstable-pod.yaml
```

### Inspect the QoS Class
```bash
kubectl get pod burstable-pod -o jsonpath='{.status.qosClass}'
```
**Expected Output:**
```text
Burstable
```

---

## Step 3: Deploy a BestEffort QoS Pod
Apply the `besteffort-pod.yaml` manifest.

```bash
kubectl apply -f ../manifests/besteffort-pod.yaml
```

### Inspect the QoS Class
```bash
kubectl get pod besteffort-pod -o jsonpath='{.status.qosClass}'
```
**Expected Output:**
```text
BestEffort
```

---

## Step 4: Verify Cgroup Files on the Worker Node (Optional / Deep Dive)
If you are using Minikube or a local Kind cluster, you can SSH into the node to see the cgroups directory.

1. Get the container ID of the `guaranteed-pod`:
   ```bash
   kubectl get pod guaranteed-pod -o jsonpath='{.status.containerStatuses[0].containerID}'
   ```
   *Example Output:* `containerd://b4bcf42867efb...`

2. Exec or SSH into the Kind node:
   ```bash
   docker exec -it kind-control-plane bash
   ```

3. Search for the cgroup settings in the path `/sys/fs/cgroup/` (for CPU/Memory):
   ```bash
   find /sys/fs/cgroup -name "*b4bcf42867efb*"
   ```

4. Inspect the cgroup memory limits (in bytes):
   - For cgroups v1:
     ```bash
     cat /sys/fs/cgroup/memory/kubepods/pod<pod-uid>/<container-id>/memory.limit_in_bytes
     ```
   - For cgroups v2:
     ```bash
     cat /sys/fs/cgroup/kubepods.slice/kubepods-pod<pod-uid>.slice/cri-containerd-<container-id>.scope/memory.max
     ```
   You will see the exact limit in bytes matching the `256Mi` limit (`268435456` bytes).

---

## Clean Up
```bash
kubectl delete pod guaranteed-pod burstable-pod besteffort-pod
```
