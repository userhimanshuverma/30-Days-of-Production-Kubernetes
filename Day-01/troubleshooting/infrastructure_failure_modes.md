# 🚨 Day 1 Troubleshooting: Infrastructure Failure Modes

Below are real-world infrastructure failure scenarios that highlight the difference between manual container operations and Kubernetes orchestration.

---

## Case 1: The "OOMKilled" Noisy Neighbor (Resource Starvation)

### Symptoms
App Alpha (a critical payment API) suddenly stops responding. The frontend logs show timeout errors connecting to App Alpha.

### Investigation (Manual Docker Era)
1. SSH into the server node hosting App Alpha.
2. Check running containers:
   ```bash
   docker ps -a
   ```
   * *Output:* App Alpha container status is `Exited (137)`.
3. Check kernel logs for system killer events:
   ```bash
   dmesg -T | grep -i oom
   ```
   * *Output:* `[Sat May 23 22:50:00 2026] Killed process 14205 (app_alpha) total-vm:4194304kB, anon-rss:2097152kB, file-rss:0kB, shmem-rss:0kB`
4. Inspect host resource usage:
   * You discover App Bravo (a background log processing script) has a memory leak and consumed 95% of server RAM, forcing the host OS kernel OOM killer to terminate App Alpha to free memory.

### Resolution & Kubernetes Prevention
* **Manual Fix:** Restart App Alpha container. Manually kill or restart App Bravo.
* **Kubernetes Hardening:** In K8s, define resource limits for App Bravo. This forces the container runtime to terminate *only* App Bravo via cgroups when it crosses its defined threshold, leaving App Alpha untouched:
  ```yaml
  resources:
    limits:
      memory: "256Mi"
  ```
  Additionally, Kubernetes would automatically detect App Alpha went down and reschedule/restart it immediately.

---

## Case 2: "Insufficient CPU/Memory" (Failed Scheduling)

### Symptoms
A deployment is triggered, but the new service is not receiving traffic. The service is stuck in a pending state indefinitely.

### Investigation (Kubernetes Era)
1. Run `kubectl get pods` to check status:
   ```bash
   kubectl get pods -l app=data-processor
   ```
   * *Output:* `data-processor-xyz-123   0/1   Pending   0   12m`
2. Describe the pod to check scheduler decisions:
   ```bash
   kubectl describe pod data-processor-xyz-123
   ```
   * *Output in Events:*
     `Warning  FailedScheduling  3m  default-scheduler  0/3 nodes are available: 3 Insufficient memory.`

### Root Cause
The data-processor requested `memory: 8Gi` in its pod specifications. However, the 3 nodes in your cluster only have 4GB of free memory each. Even though the cluster has 12GB of memory *globally*, the scheduler cannot split a single pod across multiple hosts, leading to a scheduling deadlock.

### Resolution
1. **Vertical Scaling:** Add a new node pool with larger instance types (e.g., 16GB RAM instances) to the cluster.
2. **Right-Sizing:** Review the resource requests in the manifest. If the service actually needs only 2GB RAM to boot, lower the requests:
   ```yaml
   resources:
     requests:
       memory: "2Gi"
   ```

---

## Case 3: The Orphan Container Zombie (Manual Standalone Ops)

### Symptoms
A microservice is running, but you cannot deploy updates to it. Port `8080` is reported as "already in use", but no container is listed as running on that port.

### Investigation (Standalone Docker Era)
1. Inspect running containers:
   ```bash
   docker ps
   ```
   * *Output:* No containers are listed as running on port `8080`.
2. Inspect network ports on the host system:
   ```bash
   netstat -tulnp | grep 8080
   ```
   * *Output:* `tcp 0 0 :::8080 :::* LISTEN 9205/java`
3. Inspect process tree:
   ```bash
   ps -ef | grep 9205
   ```
   * *Output:* The Java process was launched by an old Docker container process (`docker-containerd-shim`). The Docker daemon crashed and restarted, but lost track of the container child process, leaving it running as a "zombie" process bound to the network port.

### Resolution
* **Manual Fix:** Manually kill the PID: `kill -9 9205`, then restart Docker.
* **Kubernetes Prevention:** The Kubelet agent queries the host container runtime interfaces continuously. If a container becomes detached, Kubelet detects the state mismatch, terminates the stray process, cleans up the network namespaces, and restores clean service routing.
