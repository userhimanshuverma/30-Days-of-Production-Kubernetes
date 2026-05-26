# 🛠️ Lab 6: Debugging CrashLoopBackOff & OOMKilled
## 30 Days of Production Kubernetes — Day 4

In this lab, you will diagnose and resolve two of the most common container runtime failures in production: applications crashing on startup (`CrashLoopBackOff`) and applications exceeding their memory boundaries (`OOMKilled`).

---

## 🎯 Lab Objectives
1. Identify and triage a crashing Pod.
2. Extract error logs from terminated container instances.
3. Diagnose and explain `OOMKilled` errors (Exit Code 137).
4. Learn to interpret Pod event streams.

---

## 🛠️ Step-by-Step Guide

### Step 1: Deploy the Faulty Workloads
Apply the manifest file `manifests/06-broken-pod.yaml`:
```bash
kubectl apply -f manifests/06-broken-pod.yaml
```

**Expected Output:**
```text
pod/crashloop-pod created
pod/oomkilled-pod created
```

---

## 🔍 Part A: Debugging the CrashLoopBackOff

### Step 1: Check Pod Status
```bash
kubectl get pods
```

**Expected Output:**
```text
NAME             READY   STATUS             RESTARTS      AGE
crashloop-pod    0/1     CrashLoopBackOff   1 (10s ago)   20s
oomkilled-pod    0/1     ContainerCreating  0             5s
```
Notice that `crashloop-pod` is in `CrashLoopBackOff`. This status means that the Kubelet is trying to start the container, but it crashes, and Kubelet is backing off (waiting) before retrying to avoid overloading the node.

### Step 2: Describe the Pod and Inspect Events
Get the detailed lifecycle event stream:
```bash
kubectl describe pod crashloop-pod
```

Look at the **Containers / State** and **Events** sections:
* `State: Waiting / Reason: CrashLoopBackOff`
* `Last State: Terminated / Reason: Error / Exit Code: 1`
* `Events:` You will see a history of Kubelet starting the container and then detecting back-off.

### Step 3: Fetch Terminal Logs
Since the container is not currently running, standard `kubectl logs` might fail or only show the current crash. To inspect the stdout logs of the **previous crashed container instance**, run:
```bash
kubectl logs crashloop-pod -p
```

**Expected Output:**
```text
Booting service...
ERROR: Database connection failed (Timeout 15000ms)
```
The application process terminated with exit code `1` because it could not connect to a database. 

**Diagnostic Concept:**
`CrashLoopBackOff` is not a container engine failure; it is an application process failure. The container runtime successfully loaded the image and launched the entrypoint process, but the process itself crashed and terminated.

---

## 🔍 Part B: Debugging the OOMKilled Pod

### Step 1: Track the Memory Leak Status
Check the status of the second Pod:
```bash
kubectl get pods
```

**Expected Output:**
```text
NAME             READY   STATUS      RESTARTS      AGE
oomkilled-pod    0/1     OOMKilled   1 (5s ago)    35s
```
The status shows `OOMKilled`. Let's inspect the exact details.

### Step 2: Find the Exit Code & Termination Reason
```bash
kubectl describe pod oomkilled-pod
```

Look closely at the **Containers / Last State** details:
```text
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Tue, 26 May 2026 22:01:00 +0000
      Finished:     Tue, 26 May 2026 22:01:05 +0000
```

* **Why Exit Code 137?**
  Exit code `137` is calculated as $128 + \text{Signal Number}$. The signal number for a forceful kill (`SIGKILL`) is `9`. Thus, $128 + 9 = 137$. This indicates the container did not exit cleanly; it was forcefully killed by the OS kernel.
* **What triggered it?**
  The container allocated more memory than the `limits.memory` threshold defined in the Pod spec (`20Mi`). The Linux kernel cgroup out-of-memory handler detected this violation and immediately executed a `SIGKILL` on the container processes.

---

## 🛠️ Step 3: Fix the Workloads (Resolution)

To fix these pods:
1. For `crashloop-pod`: Resolve the database config or mock connection so the entrypoint process doesn't exit.
2. For `oomkilled-pod`: Increase the limit to at least `64Mi` (which can accommodate our mock 32MB file allocation) and redeploy.

### Step 4: Clean Up
```bash
kubectl delete pod crashloop-pod oomkilled-pod
```
