# 🧪 Lab 6: Use kubectl describe Effectively

## Objective
Learn how to analyze structural metadata and execution state conditions returned by `kubectl describe` to pinpoint issues like scheduling, volume mounting, and health probe failures.

---

## Step-by-Step Investigation

The output of `kubectl describe` contains structured blocks. Let's break down where to look when debugging under pressure.

### 1. Identify Pod Status Conditions
Run `describe` on any running pod in your namespace:
```bash
kubectl describe pod <pod-name>
```

Locate the `Conditions:` section. Pods transition through specific conditions:
```text
Conditions:
  Type              Status
  Initialized       True 
  Ready             True 
  ContainersReady   True 
  PodScheduled      True 
```
*   If `Ready` is `False` but `Initialized` is `True`, it indicates that the container is running but is failing its **readiness probe**.

### 2. Verify ControlledBy and Owner References
Look at the top section:
```text
Controlled By:  ReplicaSet/payment-processor-597b489d89
```
This tells you which controller spawned the pod. If you need to scale or change resources, edit this controller (e.g. Deployment, DaemonSet, StatefulSet) instead of modifying the ephemeral Pod directly.

### 3. Check Container State & Restarts
Inside the `Containers:` block:
```text
State:          Running
  Started:      Wed, 10 Jun 2026 23:30:15 +0530
Last State:     Terminated
  Reason:       Error
  Exit Code:    2
  Started:      Wed, 10 Jun 2026 23:28:10 +0530
  Finished:     Wed, 10 Jun 2026 23:29:12 +0530
Restarts:       3
```
This is critical: it captures the **previous** termination status, telling you that before the current execution, the process crashed with exit code 2.

### 4. Check Volume and Mount Structures
Locate `Mounts:` inside the container description:
```text
Mounts:
  /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-7c2v (ro)
  /app/config from config-volume (rw)
```
Ensure that permissions (`ro` - read only, `rw` - read write) and filepaths align with your application expectations.

### 5. Check Host Node IP Mapping
Check if the pod is pinned to a specific worker node:
```text
Node:             node-worker-2/192.168.1.102
```
If other pods on `node-worker-2` are also crashing, the issue is likely a host-level degraded hardware state, or CNI network mapping issues on that particular node.
