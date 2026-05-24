# 🚨 Day 02 Troubleshooting: Container Internals Diagnostics Playbook

This handbook contains production troubleshooting playbooks for resolving deep systems-level container issues.

---

## Playbook 1: Container OOMKilled (Exit Code 137)

### Symptoms
*   Pod transitions to `OOMKilled` state.
*   Container restarts repeatedly (CrashLoopBackOff).
*   Process terminates abruptly. `kubectl describe pod` outputs:
    `State: Terminated, Reason: OOMKilled, Exit Code: 137`.

### Root Cause
The process group inside the container cgroup (`/sys/fs/cgroup/memory`) exceeded its hard limit (`memory.max` / `memory.limit_in_bytes`). The kernel immediately invoked the OOM killer and sent a `SIGKILL` (signal 9) to the primary processes.

### Investigation & Diagnostics
1.  **Check Kernel Logs:** SSH to the worker node and run `dmesg` or check `/var/log/messages` to verify the kernel terminated the process:
    ```bash
    dmesg -T | grep -i -E 'oom[-_]killer|killed process'
    ```
    *Expected output:*
    `[Sun May 24 20:45:10 2026] Task 1450 (node) killed as a result of limit of /kubepods.slice/kubepods-burstable.slice/pod_uuid/container`
2.  **Inspect Memory Usage Metrics:**
    ```bash
    # View cgroup memory limit vs usage inside the container (cgroups v2)
    cat /sys/fs/cgroup/memory.max
    cat /sys/fs/cgroup/memory.current
    ```

### Resolution
*   **Immediate Fix:** Increase the memory limits (`resources.limits.memory`) in the Pod spec to accommodate memory usage peaks.
*   **Root Cause Analysis:** Profiling the application (Node.js heap dump, Go pprof, JVM memory tracker) to identify memory leaks.
*   **Tuning JVM/Node.js:** Configure the runtimes to be aware of cgroup limits (e.g. JVM `-XX:MaxRAMPercentage=75.0` or Node.js `--max-old-space-size`).

---

## Playbook 2: CFS CPU Throttling

### Symptoms
*   Application response time (p95/p99 latency) spikes significantly.
*   API requests timeout, but the average CPU usage of the container remains well below the limit (e.g., 30% average CPU).
*   Container logs show background processing queues filling up.

### Root Cause
The Completely Fair Scheduler (CFS) throttles the container's processes. The container has short bursts of intense activity that consume its entire millisecond allotment (`cpu.max` / `cpu.cfs_quota_us`) within a fraction of the cgroup period (100ms). For the remaining portion of the period, the kernel blocks the process from running.

### Investigation & Diagnostics
1.  **Query Container Throttling Stats:** Run inside the container or query from the host cgroup path:
    ```bash
    cat /sys/fs/cgroup/cpu.stat
    ```
    *Output snippet:*
    ```text
    usage_usec 450129032
    user_usec 301290322
    system_usec 148838710
    nr_periods 45000         # Total periods elapsed
    nr_throttled 12500       # Number of periods the container was throttled
    throttled_usec 876001202 # Total time the processes sat blocked in microseconds
    ```
    If `nr_throttled / nr_periods` is high (e.g., > 10%), CPU throttling is degrading performance.

### Resolution
*   **Increase CPU Limit:** Raise `resources.limits.cpu` to accommodate micro-bursts.
*   **Remove CPU Limits:** Set no CPU limit (leave `resources.limits.cpu` blank) and rely exclusively on `resources.requests.cpu` to let the kernel distribute excess idle CPU cycles dynamically.
*   **Adjust CFS Period:** (Advanced) Change Kubelet parameters to reduce the CFS quota period from 100ms to 10ms, smoothing out throttling boundaries.

---

## Playbook 3: Namespace Leakage (Host Zombie Processes)

### Symptoms
*   The worker node starts throwing errors: `fork: retry: Resource temporarily unavailable`.
*   The Kubelet reports `PIDs Limit Reached` on the node.
*   Monitoring systems alert on high overall PID counts on the node, but `kubectl get pods` shows very few active pods.

### Root Cause
Applications running inside containers are spawning child processes that terminate, but they are not being cleaned up (reaped) by PID 1. In Linux, when a child process exits, it remains in the process table as a **zombie** until its parent reads its exit status using a `wait()` system call. If PID 1 inside the container is a standard application (like Node.js or Python) rather than an init system, it does not reap orphaned zombie processes, leading to host PID table exhaustion.

### Investigation & Diagnostics
1.  **Find Zombie Processes on the Host:**
    ```bash
    ps aux | grep 'Z'
    # Or find parent process of zombie processes
    ps -ef | grep '[z]ombie'
    ```
2.  **Trace PID namespace files:** View active mounts and namespace IDs.
    ```bash
    lsns -t pid
    ```

### Resolution
*   **Enable Kubelet PID Limits:** Configure Kubelet config with `--pod-max-pids` to isolate PID consumption per pod.
*   **Use an Init Process:** In the container image, run the application using a lightweight init daemon like **tini** or configure `shareProcessNamespace: true` in the Kubernetes pod spec. Tini acts as PID 1, spawns your app as a child, and reaps all orphaned zombie processes correctly.
    ```dockerfile
    # Dockerfile snippet
    RUN apk add --no-cache tini
    ENTRYPOINT ["/sbin/tini", "--"]
    CMD ["node", "app.js"]
    ```

---

## Playbook 4: Container Escape Risk (Privileged Container Exploits)

### Symptoms
*   Security audit scanner alerts on high risk `/sys` mount writeability.
*   Unauthorized changes occur on the host operating system files (e.g. `/etc/shadow` or cron jobs modified).
*   Non-kubernetes processes running on the host system are killed or manipulated.

### Root Cause
A container was deployed with high privileges (e.g., `privileged: true` in the security context or mounting dangerous host directories like `/sys`, `/proc`, or `/var/run/docker.sock`). Attackers who compromise the container can easily write to host directories or access host device nodes (`/dev/`) to escape process isolation.

### Investigation & Diagnostics
1.  **Check Privileged Status from Inside Container:**
    ```bash
    # If this command succeeds and lists raw host disk devices, the container is privileged
    fdisk -l
    ```
2.  **Verify Host Network Capabilities:**
    ```bash
    # Check if the container can see the host network interfaces
    ip link show
    ```
    If you see host interfaces (like physical `eth0` or `bond0` instead of a single virtual `eth0`), the container was launched with `hostNetwork: true`.

### Resolution
*   **Apply Pod Security Standards (PSS):** Restrict pods to the `Baseline` or `Restricted` standards, banning `privileged: true`, `hostNetwork: true`, `hostPID: true`, and `hostIPC: true`.
*   **Enforce Read-Only Filesystems:** Mount container root filesystems as read-only to prevent write access to critical execution binaries.
*   **Drop Capabilities:** Explicitly drop all capabilities in the container's manifest and add back only what is necessary (e.g. `CAP_NET_BIND_SERVICE`).

---

## Playbook 5: containerd Daemon Socket / runc Crash

### Symptoms
*   Pods are stuck in `ContainerCreating` or `Terminating` states.
*   `kubectl get nodes` shows the node status as `NotReady`.
*   `kubectl` returns errors: `Error from server (InternalError): IPC error...`.

### Root Cause
The low-level container manager (`containerd` or `runc`) crashed, locked up, or ran out of file descriptors/sockets, leaving container processes disconnected from the control plane.

### Investigation & Diagnostics
1.  **Check containerd Daemon Logs:** SSH to the node and query systemd logs:
    ```bash
    journalctl -u containerd -n 100 --no-pager
    ```
2.  **Check OCI Runtime Status:**
    ```bash
    # Verify if containerd is responding to CLI queries
    sudo ctr containers list
    # Check low-level runc processes
    sudo runc list
    ```
3.  **Check for Disk Space Exhaustion:**
    ```bash
    df -h /var/lib/containerd
    ```
    If `/var/lib/containerd` is at 100% usage, containerd will stop responding.

### Resolution
*   **Clean Up Unused Resources:** Run `ctr images prune` or let the Kubelet garbage collector run.
*   **Restart containerd:**
    ```bash
    sudo systemctl restart containerd
    ```
    *Note: Standard containerd-shim architecture ensures that restarting containerd does NOT terminate running container processes.*

---

## Playbook 6: Filesystem Permission Denied (UID/GID Mismatches)

### Symptoms
*   The container crashes during startup.
*   Logs show: `Permission denied` or `cannot open file /data/config: Access Denied`.
*   The container has `runAsNonRoot: true` and is running as a specific UID (e.g. `10001`).

### Root Cause
The application process inside the container runs as UID `10001`. However, the files it is trying to access on a mounted volume (like a HostPath, NFS, or Persistent Volume) are owned by root (`UID 0`) or a different host user, preventing the process from reading or writing to the volume.

### Investigation & Diagnostics
1.  **Identify Running UID:**
    ```bash
    # Check the user ID inside the container
    id
    ```
2.  **Verify Volume Ownership on Host/Mount:**
    ```bash
    # Check permissions of the mounted directory
    ls -la /data
    ```
    *Output:*
    `drwxr-xr-x 2 root root 4096 May 24 15:00 config`
    Here, the directory is owned by `root`, but our container process is user `10001`, which has no write permissions.

### Resolution
*   **Configure fsGroup in Pod Security Context:** Set the `fsGroup` parameter. Kubernetes will automatically run a recursive `chown` on the volume files to match this GID during mounting.
    ```yaml
    spec:
      securityContext:
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001 # Automatically makes files readable/writable by GID 10001
    ```
*   **Fix Base Image Permissions:** Ensure your Dockerfile creates the application directory and sets permissions for the non-root user *before* building the image.

---

## Playbook 7: OverlayFS Disk Exhaustion

### Symptoms
*   Nodes report `DiskPressure` taint, eviction warnings are generated.
*   Containers fail to write files with error: `No space left on device` (even though global host disk space has capacity).
*   `docker system df` or local disk checks show extreme growth in `/var/lib/containerd/overlayfs/`.

### Root Cause
A containerized process is writing logs, temp files, or local database writes directly inside its container filesystem (which translates to the `upperdir` of OverlayFS). These temporary writes compile inside `/var/lib/containerd/overlayfs/` and consume node disk space.

### Investigation & Diagnostics
1.  **Identify Heavy Write Containers:**
    Run on the host to find the largest directories inside the overlay path:
    ```bash
    sudo du -h -d 2 /var/lib/containerd/io.containerd.runtime.v2.task/ | sort -h -r | head -n 10
    ```
2.  **Verify Container Storage Write:**
    Use `kubectl exec` to check disk usage within the container:
    ```bash
    df -h /
    ```

### Resolution
*   **Use Ephemeral Storage Limits:** Define resources limits for ephemeral storage in your Pod spec:
    ```yaml
    resources:
      limits:
        ephemeral-storage: "2Gi"
    ```
*   **Mount Volumes for Heavy I/O:** Never write persistent or heavy temporary files directly to the root container filesystem. Use `emptyDir` mounts (which can run in RAM or dedicated storage) or PersistentVolumes.

---

## Playbook 8: Network Namespace Isolation Leakage

### Symptoms
*   Containers inside different namespaces or network policies can sniff each other's traffic.
*   Two pods on the same node fail to bind to port `8080` simultaneously (throwing `Address already in use` error).

### Root Cause
The containers were accidentally deployed sharing the host network namespace (`hostNetwork: true`), or the virtual ethernet interfaces (`veth` pairs) were misconfigured by the CNI, leaking traffic across boundaries.

### Investigation & Diagnostics
1.  **Trace Network Namespaces:**
    ```bash
    # List net namespaces on host
    ip netns list
    ```
2.  **Verify Port Bindings:**
    ```bash
    # View ports listening in the host namespace
    sudo ss -tulpn
    ```

### Resolution
*   **Set `hostNetwork: false`:** Ensure that applications run inside their own isolated net namespace.
*   **Audit CNI Policy:** Verify Kubernetes NetworkPolicies are applied and CNI configuration is enforcing standard isolation rules.
