# 🏆 Exercise 1: Debugging a Failed etcd Restore

In this exercise, you will diagnose and repair a control plane that has crashed after a failed manual etcd restore attempt.

---

## 🚨 The Scenario

An SRE tried to restore a snapshot from `s3` to recover from a minor database corruption incident. They executed the restore command and restarted the nodes, but now:
* `kubectl` commands return `The connection to the server 10.0.0.11:6443 was refused - did you specify the right host or port?`
* The `kubelet` service on `control-plane-01` is running, but throwing error logs.
* The static pod files for `kube-apiserver` and `etcd` are present in `/etc/kubernetes/manifests`.

---

## 🔍 Your Investigation

You log into `control-plane-01` and check the docker/containerd container logs for etcd:
```bash
sudo crictl ps -a | grep etcd
# You notice the etcd container has exited with status 1
```

You view the logs of the failed etcd container:
```bash
sudo crictl logs <container-id>
```

**Logs Output**:
```text
2026-06-12 14:10:00.103984 E | etcdserver: open /var/lib/etcd/member/snap/db: permission denied
```

---

## 🎯 Challenge Goal

Analyze the logs and restore order, solve the issue, and bring the API server back online.

### 📋 Questions & Actions to Resolve:
1. **Identify the Root Cause**: Why did the container encounter a `permission denied` error on `/var/lib/etcd/member/snap/db`? (Hint: Think about which host user runs the command versus the container execution context).
2. **Correct the Directory Ownership**: Write the exact bash command to fix the permissions.
3. **Verify Restoration**: Write the commands you would run to verify that `etcd` has successfully started and the `kube-apiserver` is responding.

---

## 💡 Solution Guide & Walkthrough
*(Do not read this until you have attempted to solve it!)*

<details>
<summary>🔑 View Solution</summary>

### 1. Root Cause Analysis
When the SRE ran the `etcdctl snapshot restore` command, they ran it under `sudo` (root). By default, `etcdctl` creates the target directory (`/var/lib/etcd`) owned by the caller (in this case, `root:root`). 
However, in production Kubernetes configurations (like those deployed by kubeadm), the etcd container runs under a non-root system user (UID `2000` or similar) for security hardening. The container could not read or write to the newly created data directory, resulting in `permission denied` and a `CrashLoopBackOff`.

### 2. Resolution Command
You need to change the ownership of `/var/lib/etcd` back to the user that etcd runs as, or allow read/write permissions. Since kubeadm-managed etcd containers run with host paths, changing permissions to `root` or verifying the user context is needed:
```bash
# Correct ownership to root (or user 2000 depending on cluster flavor)
sudo chown -R root:root /var/lib/etcd
sudo chmod -R 700 /var/lib/etcd
```
*Note: If etcd runs as a specific non-root user (e.g. UID 2000), run: `sudo chown -R 2000:2000 /var/lib/etcd`.*

### 3. Verification
Restart the kubelet to force a reload of the static pods:
```bash
sudo systemctl restart kubelet
```
Wait 30 seconds, then check if etcd is running:
```bash
sudo crictl ps | grep etcd
```
And check if kubectl can fetch nodes:
```bash
kubectl get nodes
```
</details>
