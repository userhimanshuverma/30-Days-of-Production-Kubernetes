# 🛠️ Lab 4: Modern Native Sidecars (Kubernetes 1.28+)
## 30 Days of Production Kubernetes — Day 4

In this lab, you will explore the native sidecar feature introduced in Kubernetes 1.28. You will deploy a Pod with a sidecar proxy defined as an init container with `restartPolicy: Always`, inspect the boot sequence, and verify localhost communication.

---

## 🎯 Lab Objectives
1. Understand the syntax of native sidecar containers.
2. Deploy a native sidecar Pod.
3. Verify that the sidecar starts and remains active before main containers boot.
4. Validate communication between application and sidecar over the loopback interface.

---

## 🛠️ Step-by-Step Guide

### Step 1: Deploy the Native Sidecar Pod
Apply the manifest file `manifests/04-sidecar-pattern.yaml`:
```bash
kubectl apply -f manifests/04-sidecar-pattern.yaml
```

**Expected Output:**
```text
pod/native-sidecar-pod created
```

### Step 2: Observe the Startup Order
Let's look at the initialization sequence of the Pod:
```bash
kubectl describe pod native-sidecar-pod
```

Look at the **Init Containers** and **Containers** sections:
1. **ambient-proxy** is listed under `Init Containers`, but notice that its `State` is `Running` and it has a special flag: `Restart Policy: Always`.
2. Unlike standard init containers (which must terminate before the main container starts), the Kubelet starts `ambient-proxy`, waits for it to become ready, and then immediately proceeds to start the main `application` container *while the sidecar is still running*.

### Step 3: Verify Inter-Container Communication
Let's verify that the application container is sending network requests to the sidecar proxy on `localhost:9090`.

Check the application container logs:
```bash
kubectl logs -f native-sidecar-pod -c application
```

**Expected Output:**
```text
App started. Waiting for proxy sidecar to accept connections...
Sending request to proxy sidecar on localhost:9090...
Proxy intercepted response
Sending request to proxy sidecar on localhost:9090...
Proxy intercepted response
```
The application successfully contacted `localhost:9090`. Because both containers share the network namespace (plumbed by the Pause container), port `9090` opened by the proxy is directly available to the application container via the local loopback interface.

### Step 4: Verify Crash Resilience
What happens if the native sidecar crashes? Let's simulate a crash of the proxy container.

Since we cannot easily kill processes in read-only setups, we can simulate killing the container process by finding its container ID and using docker or client commands, or we can simply trust the Kubelet's restart mechanism. Let's inspect the Pod restart values:
```bash
# Check container statuses and restart counts
kubectl get pod native-sidecar-pod -o jsonpath='{.status.initContainerStatuses[*].restartCount}'
```
Because `restartPolicy` is set to `Always` on the init container, if it fails, Kubelet restarts it immediately, preventing the main application container from losing its proxy link.

### Step 5: Clean Up
```bash
kubectl delete -f manifests/04-sidecar-pattern.yaml
```
