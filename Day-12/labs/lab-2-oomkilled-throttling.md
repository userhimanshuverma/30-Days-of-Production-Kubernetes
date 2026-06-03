# 🛠️ Lab 2: Simulating OOMKilled & CPU Throttling

## Objective
Simulate a Memory Limit Out-Of-Memory (OOM) termination and observe how CPU limits lead to throttling.

## Prerequisites
- A running Kubernetes cluster.

---

## Step 1: Simulate OOMKilled (Exit Code 137)

Apply the `oom-pod.yaml` manifest. This Pod executes a Python script that attempts to allocate 150MB of memory, exceeding its limit of 100Mi.

```bash
kubectl apply -f ../manifests/oom-pod.yaml
```

Wait 5-10 seconds, and query the Pod status:
```bash
kubectl get pod oom-pod
```
**Expected Output:**
```text
NAME      READY   STATUS      RESTARTS   AGE
oom-pod   0/1     OOMKilled   0          12s
```

### Inspect the Failure Details
Run `describe` on the Pod:
```bash
kubectl describe pod oom-pod
```

Look at the `Containers` status section. You should see:
```text
    State:          Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Wed, 03 Jun 2026 12:00:00 +0000
      Finished:     Wed, 03 Jun 2026 12:00:05 +0000
```
- **Reason: OOMKilled** indicates that the Linux cgroup memory controller terminated the process.
- **Exit Code: 137** indicates the process was terminated by signal `9` (`SIGKILL` -> $128 + 9 = 137$).

---

## Step 2: Simulate and Observe CPU Throttling

Apply the `cpu-throttling-pod.yaml` manifest.

```bash
kubectl apply -f ../manifests/cpu-throttling-pod.yaml
```

Confirm the Pod is running:
```bash
kubectl get pod cpu-throttling-pod
```

### Check Throttling Metrics
Since Kubernetes does not expose throttling metrics in standard `kubectl describe`, you can inspect throttling by reading the cgroup files directly on the host (in a Kind/Minikube cluster), or via Prometheus metrics.

#### Option A: Cgroups inspection (On the node)
1. Find the container ID of the `cpu-throttling-pod`:
   ```bash
   kubectl get pod cpu-throttling-pod -o jsonpath='{.status.containerStatuses[0].containerID}'
   ```
   *Example Output:* `containerd://a1b2c3d4e5f6...`

2. Exec into your Kind node:
   ```bash
   docker exec -it kind-control-plane bash
   ```

3. Navigate to the cgroup cpu stat folder:
   - For cgroups v2 (modern Linux kernels):
     ```bash
     cat /sys/fs/cgroup/kubepods.slice/kubepods-pod<pod-uid>.slice/cri-containerd-<container-id>.scope/cpu.stat
     ```
   You will see output similar to:
   ```text
   usage_usec 241029302
   user_usec 230910000
   system_usec 10119302
   nr_periods 2410
   nr_throttled 1820
   throttled_usec 120930291
   ```
   - **`nr_periods`**: Total CFS periods that have passed since the container started.
   - **`nr_throttled`**: The number of periods where the container was throttled because it exceeded its CPU limit.
   - **`throttled_usec`**: Total duration of time the processes in this container were suspended. 
   
   Here, the container is throttled in over **75% of the runtime periods**, indicating that the CPU limit of `250m` is severely bottlenecking the application.

#### Option B: Prometheus Metrics (Production)
In a production cluster, you monitor CPU throttling via Prometheus alerts using this Query:
```promql
sum(rate(container_cpu_cfs_throttled_seconds_total[5m])) by (pod, container)
  /
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod, container) * 100
```
An average throttling percentage of > 10% is typically a warning sign for performance-sensitive services.

---

## Clean Up
```bash
kubectl delete pod oom-pod cpu-throttling-pod
```
