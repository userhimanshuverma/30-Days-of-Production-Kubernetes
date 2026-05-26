# 🚨 Pod Troubleshooting & Debugging Playbook
## 30 Days of Production Kubernetes — Day 4

This handbook provides step-by-step diagnostic workflows for resolving production failures related to Kubernetes Pods.

---

## 🛠️ Diagnostics Cheat Sheet

When debugging a Pod, execute this initial triage sequence:

```bash
# 1. Get high-level status of all pods
kubectl get pods -n <namespace> -o wide

# 2. Check the lifecycle event stream of a failing pod
kubectl describe pod <pod-name> -n <namespace>

# 3. Stream the container standard output logs (add -p for previous crashed instances)
kubectl logs <pod-name> -n <namespace> -c <container-name> --tail=100

# 4. Spin up an ephemeral debug container inside the same network/PID namespace
kubectl debug -it <pod-name> --image=busybox --target=<container-name>
```

---

## 📋 10 Common Production Failure Scenarios

### 1. `CrashLoopBackOff`
* **Symptoms:** Pod alternates between `Running` and `Error` or `CrashLoopBackOff`. The restart counter increases.
* **Root Cause:** The application process inside the container started, but immediately exited with a non-zero code. This could be due to syntax errors, missing configurations, failed database connections, or permission errors.
* **Investigation:**
  ```bash
  # Check if there is an exit code in the container state
  kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[*].state.waiting}'
  
  # Fetch logs from the PREVIOUS (crashed) instance of the container
  kubectl logs <pod-name> -p
  ```
* **Resolution:** Fix the application code, supply the missing environment variables, or update the startup script permissions.
* **Prevention:** Ensure the app process does not crash on startup if external dependencies are missing (use backoffs or health endpoints instead).

---

### 2. `ImagePullBackOff` / `ErrImagePull`
* **Symptoms:** Pod remains in `ImagePullBackOff` or `ErrImagePull`.
* **Root Cause:** Kubelet cannot fetch the container image. This is caused by registry rate limits, private registry authentication errors, typos in the image name, or non-existent tags.
* **Investigation:**
  ```bash
  # Check Events section for registry access logs
  kubectl describe pod <pod-name>
  ```
  Look for: `Failed to pull image ... unauthorized: authentication required` or `manifest for ... not found`.
* **Resolution:** 
  * Fix the spelling of the image tag.
  * Recreate the `imagePullSecrets` Secret.
  * Verify the service account has permission to read the secret.
* **Prevention:** Use an internal proxy or mirror for Docker Hub to avoid rate limiting.

---

### 3. `FailedScheduling`
* **Symptoms:** Pod remains in `Pending` state. `kubectl get pods` shows status as `Pending`.
* **Root Cause:** The scheduler cannot find a node in the cluster that satisfies the Pod's resource requirements, node selectors, taints/tolerations, or affinity rules.
* **Investigation:**
  ```bash
  # Check the events to see scheduler decisions
  kubectl describe pod <pod-name>
  ```
  Look for: `0/3 nodes are available: 3 Insufficient cpu.` or `3 node(s) had untolerated taint`.
* **Resolution:**
  * Lower the `resources.requests` values.
  * Add more worker nodes (scale cluster autoscaler).
  * Align the Pod tolerations with node taints.
* **Prevention:** Implement cluster-wide resource quotas and limit ranges.

---

### 4. `OOMKilled` (Exit Code 137)
* **Symptoms:** Pod restarts, `kubectl describe` shows: `OOMKilled: true` or container terminated with exit code `137`.
* **Root Cause:** The container process requested more memory than its limit (`resources.limits.memory`) allowed. The Linux kernel terminated the process using `SIGKILL`.
* **Investigation:**
  ```bash
  kubectl describe pod <pod-name>
  ```
  Look for `Last State: Terminated`, `Reason: OOMKilled`, `Exit Code: 137`.
* **Resolution:** Increase the memory limit in the Pod specification. Profile the application for memory leaks.
* **Prevention:** Configure appropriate heap limits (e.g. `-XX:MaxRAMPercentage` for Java) so the application garbage-collects before hitting the cgroup threshold.

---

### 5. Readiness/Liveness Probe Failures
* **Symptoms:** 
  * *Readiness fail:* Pod shows status `Running` but `READY` column is `0/1`. The Pod receives no traffic.
  * *Liveness fail:* Pod restarts repeatedly. Kubelet events show `Liveness probe failed`.
* **Root Cause:** The health check endpoint in the container did not respond with a HTTP `2xx`/`3xx` status, or command check timed out.
* **Investigation:**
  ```bash
  kubectl describe pod <pod-name>
  # Read the probe port and path, then port-forward to test manually:
  kubectl port-forward <pod-name> 8080:8080
  curl -iv http://localhost:8080/healthz
  ```
* **Resolution:** Fix app deadlocks, optimize database response times, or adjust probe settings (`timeoutSeconds`, `initialDelaySeconds`).
* **Prevention:** Decouple dependency checks from liveness probes.

---

### 6. Init Container Hangs
* **Symptoms:** Pod remains in `Pending` or `Init:0/1` state.
* **Root Cause:** The init container is looping or stuck (e.g., waiting for database migration, waiting for DNS resolution of a service).
* **Investigation:**
  ```bash
  # Print logs of the specific init container
  kubectl logs <pod-name> -c <init-container-name>
  ```
* **Resolution:** Ensure the dependency that the init container is waiting for is online and accessible.
* **Prevention:** Configure a timeout inside the init container script so it fails explicitly rather than hanging indefinitely, allowing the pod to restart and log the error.

---

### 7. Sidecar Connection Timeouts
* **Symptoms:** The main application container crashes because it fails to connect to local services (e.g. localhost proxy) during boot.
* **Root Cause:** The main application container started executing before the sidecar proxy (like Istio Envoy or database proxy) was fully up and listening.
* **Investigation:**
  Check application logs: `Connection refused: localhost:15001` or similar.
* **Resolution:**
  * Use native sidecars (Kubernetes 1.28+) with `restartPolicy: Always`.
  * Add a startup delay/wait loop to the application startup script.
* **Prevention:** Always ensure apps have robust connection retry logic.

---

### 8. Volume Mount Failures
* **Symptoms:** Pod remains in `ContainerCreating` or `UnexpectedAdmissionError`.
* **Root Cause:** The volume could not be attached or mounted to the node. Common causes: CSI driver crashing, cloud volume still attached to a dead node (multi-attach error), or incorrect path permissions.
* **Investigation:**
  ```bash
  kubectl describe pod <pod-name>
  ```
  Look for events like: `FailedAttachVolume`, `Multi-Attach error for volume`, or `MountVolume.SetUp failed`.
* **Resolution:** Force detach the volume via your cloud provider console, restart the CSI controller pods, or fix volume permission configurations.
* **Prevention:** Use ReadWriteMany (RWX) volumes if sharing between multiple pods on different nodes is required.

---

### 9. Pod Eviction (`Evicted`)
* **Symptoms:** Pod status shows `Evicted`.
* **Root Cause:** The worker node ran out of resources (usually disk space or memory). The Kubelet evicted lowest priority pods (BestEffort or Burstable) to protect node stability.
* **Investigation:**
  ```bash
  kubectl describe pod <pod-name>
  ```
  Look for `Status: Failed`, `Reason: Evicted`, and message details like `The node was low on resource: ephemeral-storage`.
* **Resolution:** Clean up host logs, delete unused Docker images, or scale the node disk size.
* **Prevention:** Define correct memory/CPU requests and limits (Guaranteed QoS class) so Kubelet preserves the pod.

---

### 10. Node Pressure Conditions
* **Symptoms:** Pods on a specific node transition to `Pending` or fail scheduler selection.
* **Root Cause:** The host node has marked itself as unhealthy due to resource exhaustion (e.g. `MemoryPressure`, `DiskPressure`, `PIDPressure`).
* **Investigation:**
  ```bash
  kubectl get nodes
  kubectl describe node <node-name>
  ```
  Check the `Conditions` block to see which pressure flag is set to `True`.
* **Resolution:** Evict manual workloads, scale nodes horizontally, or increase resource availability.
* **Prevention:** Configure active cluster autoscaling and set Pod disruption budgets (PDBs).
