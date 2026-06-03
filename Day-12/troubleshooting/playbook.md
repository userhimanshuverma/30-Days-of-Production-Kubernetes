# 🚨 Troubleshooting Playbook: Scheduling & Resource Failures

This playbook provides actionable steps to diagnose and resolve common Kubernetes scheduling, resource starvation, and allocation errors.

---

## Scenario A: Pending Pods (`FailedScheduling`)

### Symptoms
The Pod status remains in `Pending`. `kubectl get pods` shows:
```text
NAME      READY   STATUS    RESTARTS   AGE
web-api   0/1     Pending   0          5m
```

### Investigation
1. Run `describe` on the Pod:
   ```bash
   kubectl describe pod <pod-name>
   ```
2. Inspect the **Events** block at the bottom for warning messages containing:
   - `0/N nodes are available: N Insufficient cpu`
   - `0/N nodes are available: N Insufficient memory`
   - `0/N nodes are available: N node(s) had untolerated taint`

3. Verify node allocatable requests:
   ```bash
   kubectl describe nodes | grep -A 5 "Allocated resources"
   ```

### Resolution
- **Option 1:** Reduce the resource requests in the Pod's YAML manifest.
- **Option 2:** Scale up your node pool by adding more nodes or provisioning larger instance sizes.
- **Option 3:** Verify that your Pod has the correct **Tolerations** matching any Node **Taints**.

---

## Scenario B: Container terminated with `OOMKilled` (Exit Code 137)

### Symptoms
Container restarts repeatedly. `kubectl get pods` shows:
```text
NAME      READY   STATUS             RESTARTS   AGE
db-app    0/1     CrashLoopBackOff   4          10m
```

### Investigation
1. Inspect Pod details:
   ```bash
   kubectl describe pod <pod-name>
   ```
2. Look at the container's status. Reason will show **`OOMKilled`** with **`Exit Code: 137`**.
3. Check the Pod's events for OOM warnings.
4. Retrieve previous container logs (if available):
   ```bash
   kubectl logs <pod-name> --previous
   ```
   Look for memory allocation errors (e.g., `OutOfMemoryError` in Java, `fatal error: out of memory` in Go).

### Resolution
- **Immediate:** Increase the `resources.limits.memory` in the Pod spec.
- **Optimization:** Run memory profiling on the application to detect memory leaks.
- **Java Workloads:** Adjust JVM heap size flags (`-Xmx`) to ensure the heap size is set to ~70% of the container memory limit.

---

## Scenario C: CPU Throttling (Degraded Performance)

### Symptoms
Application exhibits slow response times and latency spikes (p99) despite low average CPU usage reported in metrics dashboards.

### Investigation
1. If you have Prometheus configured, query the rate of throttled periods:
   ```promql
   sum(rate(container_cpu_cfs_throttled_seconds_total[5m])) by (pod, container)
   ```
2. Or, inspect the container cgroup statistics file `cpu.stat` on the worker node:
   ```bash
   cat /sys/fs/cgroup/cpu/kubepods/pod<uid>/cpu.stat
   ```
   Look at `nr_throttled` compared to `nr_periods`.

### Resolution
- **Option 1:** Raise the `resources.limits.cpu` in the container spec.
- **Option 2:** Remove the CPU limit completely if your team supports it, relying on CPU requests (`cpu.shares`) for scheduling guarantees.
- **Option 3:** Modify the application threads or GOMAXPROCS setting to match the container's CPU allocation.

---

## Scenario D: Pod Evictions due to Node Disk/Memory Pressure

### Symptoms
Pods are terminated abruptly. Status shows `Evicted`. Events report:
```text
The node was low on resource: [MemoryPressure] or [DiskPressure]
```

### Investigation
1. Identify which nodes are experiencing pressure:
   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,PRESSURE:.status.conditions[?(@.status=="True")].type
   ```
2. Inspect the events on the affected node:
   ```bash
   kubectl get events --field-selector reason=NodeHasDiskPressure
   ```

### Resolution
- **Memory Pressure:** Evicted Pods will reschedule on other nodes. If all nodes are full, scale up the cluster nodes or set up autoscaling rules. Ensure BestEffort Pods are quarantined to non-production nodes.
- **Disk Pressure:** Clean up unused Docker images and local volumes. Increase root disk sizes on nodes. Optimize application logging (forward to centralized aggregators and rotate logs).
