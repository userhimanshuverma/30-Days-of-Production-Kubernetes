# 🛠️ Lab 1: Creating & Inspecting Basic Pods
## 30 Days of Production Kubernetes — Day 4

In this lab, you will deploy a basic, production-hardened Pod to understand the core metadata structure, resource boundaries, and security contexts applied by Kubernetes.

---

## 🎯 Lab Objectives
1. Deploy a basic Pod configuration.
2. Inspect Pod parameters, namespaces, and runtime events.
3. Validate security context constraints.
4. Access the container shell.

---

## 🛠️ Step-by-Step Guide

### Step 1: Deploy the Basic Pod Manifest
Create the Pod using the manifest file `manifests/01-basic-pod.yaml`:
```bash
kubectl apply -f manifests/01-basic-pod.yaml
```

**Expected Output:**
```text
pod/production-web created
```

### Step 2: Track Pod Status
Observe the Pod initialization phase:
```bash
kubectl get pods -w
```

Watch how it transitions from `Pending` (scheduling and image downloading) to `ContainerCreating` (namespace creation and storage mapping) to `Running`.

### Step 3: Inspect Pod Details and Events
Query the Kubernetes API for the Pod state and execution history:
```bash
kubectl describe pod production-web
```

Review the output sections:
* **IP:** The IP address allocated to the Pod namespace by the CNI plugin.
* **Controlled By:** Check if it has a owner reference (it will say `None` because this is a bare Pod, not managed by a Deployment).
* **Containers / State:** Look for `Running` and the start timestamp.
* **Events:** A chronological timeline of Kubelet actions (scheduling, pulling image, creating container, starting container).

### Step 4: Validate Security Context Constraints
Our manifest configures the container to run as a non-root user (`runAsUser: 10001`) with a read-only root filesystem. Let's verify these constraints.

1. **Check the active user inside the container:**
   ```bash
   kubectl exec -it production-web -- whoami
   ```
   *Expected Output:* `10001` (demonstrates that the process does not run as root).

2. **Verify the Read-Only Root Filesystem:**
   Attempt to create a file in the root directory:
   ```bash
   kubectl exec -it production-web -- touch /failed-write.txt
   ```
   *Expected Output:*
   ```text
   touch: /failed-write.txt: Read-only file system
   command terminated with exit code 1
   ```
   This confirms that if a hacker exploits a vulnerability in the web server, they cannot modify system files or inject scripts directly into the root container image layers.

### Step 5: Clean Up
Delete the Pod to release cluster resources:
```bash
kubectl delete -f manifests/01-basic-pod.yaml
```
