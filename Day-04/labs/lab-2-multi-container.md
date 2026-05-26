# 🛠️ Lab 2: Multi-Container Shared Volume Operations
## 30 Days of Production Kubernetes — Day 4

In this lab, you will deploy a multi-container Pod where an application container writes logs to a shared storage volume, and a helper sidecar container tails and filters those logs. This simulates a production log shipper architecture.

---

## 🎯 Lab Objectives
1. Deploy a multi-container Pod.
2. Verify that both containers start inside a single scheduling unit.
3. Inspect how an `emptyDir` volume is mapped to different container paths.
4. Verify log extraction from the helper sidecar.

---

## 🛠️ Step-by-Step Guide

### Step 1: Deploy the Multi-Container Pod
Apply the manifest file `manifests/02-shared-storage.yaml`:
```bash
kubectl apply -f manifests/02-shared-storage.yaml
```

**Expected Output:**
```text
pod/shared-storage-pod created
```

### Step 2: Verify Pod Container States
Check the Pod status. Observe the `READY` column:
```bash
kubectl get pods
```

**Expected Output:**
```text
NAME                 READY   STATUS    RESTARTS   AGE
shared-storage-pod   2/2     Running   0          15s
```
Notice the `2/2` status. This means **both** the `app-writer` container and the `log-exporter` container have started successfully. If either container failed, the Ready status would show `1/2` or `0/2`.

### Step 3: Inspect Shared Volume Configuration
Let's examine how the volume is defined. Run:
```bash
kubectl get pod shared-storage-pod -o jsonpath='{.spec.volumes}'
```
You will see that a volume named `shared-logs` is defined as an `emptyDir: {}`.

Now, check how this volume is mounted inside each container:
* **app-writer volumeMount:**
  ```bash
  kubectl get pod shared-storage-pod -o jsonpath='{.spec.containers[0].volumeMounts}'
  ```
  MountPath: `/var/log/app` (Read-Write).
* **log-exporter volumeMount:**
  ```bash
  kubectl get pod shared-storage-pod -o jsonpath='{.spec.containers[1].volumeMounts}'
  ```
  MountPath: `/var/log/app` (Read-Only: `true`).

This demonstrates that while both containers access the same physical storage folder on the node, the helper sidecar is locked down to read-only access to prevent it from tampering with application logs.

### Step 4: Verify Log Aggregation
Check the logs of the `log-exporter` sidecar container. Since there are multiple containers, you must use the `-c` flag to select the container:
```bash
kubectl logs shared-storage-pod -c log-exporter
```

**Expected Output:**
```text
Starting Log Exporter sidecar...
Tue May 26 21:55:00 UTC 2026 [INFO] Transaction completed successfully
Tue May 26 21:55:05 UTC 2026 [INFO] Transaction completed successfully
Tue May 26 21:55:10 UTC 2026 [INFO] Transaction completed successfully
```
This proves the sidecar container has successfully read and printed the log entries created by the writer container on the shared disk interface.

### Step 5: Clean Up
```bash
kubectl delete -f manifests/02-shared-storage.yaml
```
