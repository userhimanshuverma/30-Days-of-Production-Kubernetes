# 🚨 Incident Scenario 3: The Cascading Pod Eviction Storm
**Severity:** Sev1 (Degraded System Performance)  
**MTTR:** 35 Minutes  
**Impact:** Key microservices evicted, scheduling delays, and intermittent request drops.

---

## 1. Alerting & Symptoms
At `23:45:00 UTC`, the SRE team received multiple PagerDuty notifications:
```text
[CRITICAL] Kubernetes Node node-worker-3: DiskPressure is True
[CRITICAL] Pod eviction rate: pods_evicted_total > 5 in last 5m (current: 12)
```
Simultaneously, Grafana dashboards show a spike in scheduling latencies for pods in the `production` namespace.

---

## 2. Incident Timeline & Investigation

### 23:48 - Triage Phase
SRE checks the node statuses first:
```bash
kubectl get nodes
```
**Output:**
```text
NAME            STATUS     ROLES    AGE    VERSION
node-master-1   Ready      control  190d   v1.28.2
node-worker-1   Ready      worker   190d   v1.28.2
node-worker-2   Ready      worker   190d   v1.28.2
node-worker-3   NotReady   worker   190d   v1.28.2
```
`node-worker-3` has transitioned to `NotReady` or is degraded. SRE runs describe on the node:
```bash
kubectl describe node node-worker-3
```
**Output:**
```text
Conditions:
  Type             Status  Reason             Message
  DiskPressure     True    KubeletHasDisk...  Kubelet has disk pressure
  MemoryPressure   False   KubeletHasNo...    Kubelet has no memory pressure
  Ready            False   NodeStatusUnknown  Kubelet stopped posting status
```
The node is reporting critical `DiskPressure`.

### 23:54 - Eviction Auditing
SRE lists recently evicted pods:
```bash
kubectl get pods --all-namespaces | grep -i evicted
```
**Output:**
```text
production    order-api-6b75c-abc12        0/1   Evicted   0          2m
production    payment-api-5c42a-def34      0/1   Evicted   0          1m
production    user-service-f321c-ghi56     0/1   Evicted   0          45s
```
Because the node experienced disk pressure, the kubelet initiated aggressive pod evictions of lower-priority BestEffort and Burstable workloads to reclaim disk space. 

### 23:58 - SSH Forensics
SRE logs into `node-worker-3` to check the root filesystem:
```bash
df -h
```
**Output:**
```text
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p1   80G   77G  3.0G  96% /
```
The `/` partition is at 96% utilization. SRE checks which directories are consuming space:
```bash
du -sh /var/lib/docker/* | sort -hr | head -n 5
```
**Output:**
```text
45G     /var/lib/docker/containers
22G     /var/lib/docker/overlay2
```
A single container is writing massive log files directly to stdout, filling up `/var/lib/docker/containers` with unrotated JSON log files.

---

## 3. Root Cause Analysis (5 Whys)

1. **Why did the node report DiskPressure?** The root filesystem crossed the 90% utilization threshold.
2. **Why?** The Docker container logs folder grew to 45GB.
3. **Why?** A debug flag (`LOG_LEVEL=DEBUG`) was set in the `payment-api` config, generating 50MB of logs per minute under production traffic.
4. **Why did this fill the node's disk?** The container runtime (containerd/docker) did not have log rotation policies configured at the OS level.
5. **Why was it not caught?** There was no monitoring alert for node disk partition growth rates.

---

## 4. Mitigation & Resolution
*   **00:05 UTC:** SRE drains the degraded node:
    ```bash
    kubectl drain node-worker-3 --ignore-daemonsets --delete-emptydir-data --force
    ```
*   **00:10 UTC:** SRE performs system cleanup on the host:
    ```bash
    docker system prune -a --volumes -f
    ```
    *(For containerd: `crictl rmi --prune`)*
*   **00:15 UTC:** SRE updates the log configuration in the `payment-api` ConfigMap to `LOG_LEVEL=WARN` and applies it:
    ```bash
    kubectl rollout restart deployment/payment-api -n production
    ```
*   **00:20 UTC:** Node disk usage drops to 40%, the node transitions back to `Ready`, and evicted pods reschedule successfully on other nodes.

---

## 5. Prevention Action Items
*   **Log Rotation:** Configure `containerd` config `containerd.toml` with strict maximum log size limits (e.g. `max-size: 10m`, `max-file: 3`).
*   **Ephemeral Storage Quotas:** Set `resources.requests.ephemeral-storage` and `resources.limits.ephemeral-storage` in pod specifications to prevent individual pods from exhausting host disk space.
*   **Alerting:** Set up PagerDuty alerts for `/var/lib/docker` disk utilization > 80% with a predictive warning (`predict_linear`).
