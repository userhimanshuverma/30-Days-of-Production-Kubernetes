# 🧪 Lab 2: Investigate OOMKilled Pods

## Objective
Learn how to identify and resolve containers terminated by the Linux Out-Of-Memory (OOM) killer due to memory resource constraints.

## Broken Environment
We will use [oomkilled-mem-leak.yaml](../manifests/oomkilled-mem-leak.yaml) which deploys a Python app that consumes memory sequentially until it exceeds its 50Mi memory limit.

---

## Step-by-Step Investigation

### 1. Apply the Broken Manifest
Apply the leaker deployment:
```bash
kubectl apply -f ../manifests/oomkilled-mem-leak.yaml
```

### 2. Monitor Pod Status
Watch the pod transitions. You might need to wait 10–20 seconds:
```bash
kubectl get pods -l app=memory-leaker -w
```

**Expected Transition Output:**
```text
NAME                             READY   STATUS    RESTARTS   AGE
memory-leaker-54bf9d123-ab45c    1/1     Running   0          5s
memory-leaker-54bf9d123-ab45c    0/1     OOMKilled 0          15s
memory-leaker-54bf9d123-ab45c    0/1     CrashLoopBackOff 1 (2s ago) 17s
```

### 3. Deep-Dive with describe
Inspect the container state metadata to confirm the termination cause:
```bash
kubectl describe pod -l app=memory-leaker
```

**Key Section to Inspect:**
```text
Containers:
  leaker:
    State:          Waiting
      Reason:       CrashLoopBackOff
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Wed, 10 Jun 2026 23:25:01 +0530
      Finished:     Wed, 10 Jun 2026 23:25:15 +0530
```
*   **Reason: OOMKilled** indicates that the Linux cgroup boundary was hit.
*   **Exit Code: 137** confirms the process was killed using `SIGKILL` (128 + 9).

---

## Resolution Walkthrough

Depending on the application analysis, resolving an OOMKilled state requires either fixing a software memory leak or right-sizing the resources limits.

### Option A: Resource Patching (Mitigation)
If the application legitimately requires more than 50Mi of memory, patch the resource limit to a higher value (e.g. 150Mi):
```bash
kubectl patch deployment memory-leaker --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value":"150Mi"}]'
```

### Option B: Fix the Code (Remediation)
If it's a memory leak, developers must profile the code. In our manifest:
1. Open [oomkilled-mem-leak.yaml](../manifests/oomkilled-mem-leak.yaml).
2. Examine the code logic: it continuously appends chunks of string data to `memory_sink` list inside an infinite loop.
3. To stabilize without expanding RAM, clear the memory buffer or pagination rules must be set.
   *(For this lab, apply Option A to watch the container stabilize in Running state)*
```bash
kubectl get pods -l app=memory-leaker
```
*Verify that the status remains `Running` without restarts.*
