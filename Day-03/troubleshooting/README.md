# 🚨 Day 3 Troubleshooting Playbook: Control Plane Recovery

This runbook provides step-by-step procedures to diagnose, isolate, and recover from failures in the Kubernetes control plane and node agent components.

---

## 🛑 Scenario 1: API Server Unavailable / Connection Refused

### Symptoms:
* `kubectl` commands return `Unable to connect to the server: dial tcp: connection refused` or `HTTP 500 / 503`.
* Node logs show failures communicating with the control plane.

### Root Cause Analysis & Investigation:
1. **Host-Level Process check:**
   Check if the API Server container is running on the master node:
   ```bash
   # Exec into master node or check docker if self-hosted / kind
   docker ps | grep apiserver
   ```
2. **Kubelet Status on Control Plane Node:**
   If the container is missing, check the host's Kubelet logs, as it is responsible for launching the API Server static pod:
   ```bash
   journalctl -u kubelet -n 100 -f
   ```
   *Look for: `Failed to start static pod "kube-apiserver"...`*
3. **Inspect API Server logs:**
   If the container keeps crashing (CrashLoopBackOff), extract the logs:
   ```bash
   docker logs $(docker ps -a | grep apiserver | head -n 1 | awk '{print $1}')
   ```
   *Look for common errors:*
   * `Failed to create etcd client: ... context deadline exceeded` (API Server cannot contact etcd).
   * `address already in use` (Port 6443 conflict).
   * TLS certificate signature errors.

### Resolution & Prevention:
* **Verify etcd is running:** The API Server will crash-loop if it cannot write/read to etcd. Troubleshoot etcd first (see Scenario 2).
* **Fix Certificate Expiry:** If logs report expired TLS certs, regenerate them:
   ```bash
   kubeadm certs renew apiserver
   ```

---

## 🛑 Scenario 2: etcd Quota Exceeded / Read-Only Database (NOSPACE alarm)

### Symptoms:
* API Server is running, but attempting to write any resource (e.g., applying a ConfigMap) returns:
  `Error from server (InternalError): write tcp ... i/o timeout` or `etcdserver: mvcc: database space exceeded`.

### Diagnostic Commands:
1. Check the etcd cluster alarms:
   ```bash
   etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     alarm list
   ```
   *Expected Output: `memberID:123456789 alarm:NOSPACE`*

### Resolution:
1. **Get current revision:**
   ```bash
   etcdctl --endpoints=https://127.0.0.1:2379 --cacert=... --cert=... --key=... endpoint status --write-out=table
   ```
   Note the current revision number.
2. **Force compaction:** Compact all revision history up to the current revision:
   ```bash
   etcdctl --endpoints=... --cacert=... --cert=... --key=... compact <REVISION_NUMBER>
   ```
3. **Defragment the database:** Defragmentation is required to release the compacted blocks back to the OS file system:
   ```bash
   etcdctl --endpoints=... --cacert=... --cert=... --key=... defrag
   ```
4. **Disarm the alarm:** Once space is freed, you must explicitly disarm the etcd lockout alarm:
   ```bash
   etcdctl --endpoints=... --cacert=... --cert=... --key=... alarm disarm
   ```

---

## 🛑 Scenario 3: Pods Stuck in Pending (Scheduler Failures)

### Symptoms:
* You run `kubectl apply` but Pods remain in `Pending` state indefinitely.

### Diagnostic Flow:
1. Check the Pod events:
   ```bash
   kubectl describe pod <pod-name>
   ```
   Look at the **Events** block at the bottom:
   * **If no events exist:** The scheduler has not even scanned the pod yet. The Scheduler service might be offline.
   * **If event shows `FailedScheduling`:**
     * `0/3 nodes are available: 3 Insufficient cpu.` (Resource constraint).
     * `node(s) had untolerated taint.` (Taint/Toleration mismatch).
     * `3 node(s) did not match PodTopologySpread.` (Affinity/Topology constraint).

2. **Verify Scheduler Status:**
   Check the scheduler pod logs in the `kube-system` namespace:
   ```bash
   kubectl logs -n kube-system -l component=kube-scheduler
   ```

### Resolution:
* **Resource Deficit:** Resize worker nodes, scale down unneeded workloads, or add a cluster autoscaler.
* **Taint Mismatch:** Add the appropriate toleration to the Pod spec, or remove the taint from the nodes:
  ```bash
  kubectl taint nodes <node-name> key:NoSchedule-
  ```

---

## 🛑 Scenario 4: Node in "NotReady" State (Kubelet Disconnect)

### Symptoms:
* `kubectl get nodes` reports worker node status is `NotReady`.
* Pods scheduled on the node transition to `Terminating` or `Unknown`.

### Investigation Steps:
1. SSH into the failed worker node and inspect Kubelet status:
   ```bash
   systemctl status kubelet
   ```
2. **If Kubelet service is stopped:** Restart it and check logs:
   ```bash
   systemctl restart kubelet
   journalctl -u kubelet -f -n 100
   ```
3. **Common Log Errors:**
   * `Failed to locate container runtime: ... connection refused` (The container runtime, e.g. containerd, crashed).
   * `Failed to validate certificate: ... certificate has expired` (Node certificates are out of sync).
   * `disk pressure threshold exceeded` (Host disk space is full).

### Resolution:
* **Disk Full:** Clean up unused Docker images and logs:
  ```bash
  crictl rmi --prune
  df -h
  ```
* **Container Runtime Restart:** If containerd is dead, restart it:
  ```bash
  systemctl restart containerd
  ```

---

## 🛑 Scenario 5: Admission Webhook Deadlock (Control Plane Instability)

### Symptoms:
* Any write request to the API Server (e.g., `kubectl apply`) times out or returns:
  `Internal error occurred: error calling webhook "validation.gatekeeper.sh": Post "https://gatekeeper-webhook-service.gatekeeper-system.svc:443/v1/admit": context deadline exceeded`.

### Root Cause:
A validating or mutating admission webhook is deadlocked, offline, or cannot receive traffic due to broken network policies, blocking the entire API Server pipeline.

### Emergency Recovery:
If the webhook pod itself is offline and you cannot delete or update it because the webhook blocks all delete/update requests, you must temporarily bypass the webhook.

1. List the configured validating webhook configurations:
   ```bash
   kubectl get validatingwebhookconfigurations
   ```
2. Force delete the blocking webhook configuration:
   ```bash
   # Add --dry-run=client -o yaml to inspect first if needed
   kubectl delete validatingwebhookconfiguration <webhook-name> --grace-period=0 --force
   ```
   *Since webhook configurations are cluster-wide metadata resources, removing the configuration instantly bypasses the webhook handler chain in the API Server.*
3. Fix the underlying webhook deployment (e.g., fix network policies, repair deployment configs) and re-apply the webhook configuration once healthy.
